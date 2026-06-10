# Phase 4 Design: Match / Inventory / Message Repositories

## Status

Tracked by GitHub Issues #163 (parent), #167 (Phase 4 sub-issue).
Last updated: 2026-06-10.

## Scope

Replace the 637 lines of handlers in `matches.rs` (507), `inventory.rs` (74),
and `messages.rs` (56) with thin handlers backed by:

1. **`MatchRepository`** — abstract + sqlx impl, with the **N+1 query fix**
   for `list_matches` (currently 1 + 3N queries → 1 + 2 batched IN queries)
2. **`InventoryRepository`** — abstract + sqlx impl
3. **`MessageRepository`** — abstract + sqlx impl
4. **`MatchLifecycleService`** — the state-machine logic that today is
   inlined in 3 handler functions (`offer_trade`, `update_match_status`,
   `apply_trade_inventory`). Each has its own `BEGIN; ... COMMIT;` block
   with `FOR UPDATE` locks, state transition validation, and cascade
   deletes.

## File Layout

```
backend/src/
├── repositories/
│   ├── mod.rs
│   ├── match_.rs        # NEW: MatchRepository trait + PgMatchRepository
│   ├── inventory.rs     # NEW: InventoryRepository trait + PgInventoryRepository
│   ├── message.rs       # NEW: MessageRepository trait + PgMessageRepository
│   ├── merch.rs         # (Phase 3, unchanged)
│   ├── group.rs         # (Phase 3, unchanged)
│   └── user.rs          # (Phase 2, unchanged)
├── services/
│   ├── mod.rs
│   ├── match_lifecycle.rs  # NEW: state-machine + tx wrapping
│   ├── merch_permissions.rs  # (Phase 3, unchanged)
│   └── permissions.rs       # (Phase 2, unchanged)
├── handlers/
│   ├── matches.rs       # SHRINKS to ~6 thin handler functions
│   ├── inventory.rs     # SHRINKS to 2 thin handlers
│   └── messages.rs      # SHRINKS to 2 thin handlers
└── routes.rs            # 3 new repos + lifecycle service in AppState
```

## Trait Method Sketches

### `MatchRepository`

```rust
pub trait MatchRepository: Send + Sync {
    /// List all matches (admin).
    fn list_all<'a>(&'a self) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>>;

    /// List matches for a user with all related data pre-loaded.
    /// This replaces the current N+1 implementation in `list_matches`
    /// (1 + 3N queries) with 1 + 2 queries (1 for matches, 1 batched
    /// for haves+selected_items, 1 batched for wants).
    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<TradeMatch>, AppError>>;

    /// Insert a pending match between two users (used by the background
    /// `matching::run_matching_algorithm` job; for now we keep that job's
    /// SQL inline — Phase 4 leaves it as a follow-up).
    fn insert_pending<'a>(
        &'a self,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<i32, AppError>>;

    /// Lock a match row for update (returns the row's user1/user2/status).
    /// Used inside the MatchLifecycleService transactions.
    fn lock_for_update<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<LockedMatch>, AppError>>;

    /// Update a match's status (used by lifecycle).
    fn set_status<'a>(
        &'a self,
        match_id: i32,
        status: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Mark a match OFFERED with the offering user's id.
    fn mark_offered<'a>(
        &'a self,
        match_id: i32,
        offered_by: i32,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Set user1_inventory_applied_at or user2_inventory_applied_at.
    fn set_user_inventory_applied<'a>(
        &'a self,
        match_id: i32,
        is_user1: bool,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Delete all other PENDING matches between two users (called on ACCEPT).
    fn purge_other_pending<'a>(
        &'a self,
        exclude_match_id: i32,
        user1_id: i32,
        user2_id: i32,
    ) -> RepositoryFuture<'a, Result<u64, AppError>>;

    /// Get the `offered_by` and the applied flags for status checks.
    fn get_status_snapshot<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<MatchStatusSnapshot>, AppError>>;

    /// Insert one match_item row (used by the offer endpoint loop).
    fn insert_match_item<'a>(
        &'a self,
        match_id: i32,
        merch_id: i32,
        owner_id: i32,
        direction: &'a str,
        quantity: i32,
    ) -> RepositoryFuture<'a, Result<MatchItem, AppError>>;

    /// Delete all match_items for a match (called on REJECTED).
    fn delete_match_items<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<u64, AppError>>;

    /// Fetch all match_items for a match (used by apply_inventory).
    fn list_match_items<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<MatchItem>, AppError>>;

    /// Notification counts: pending / offers_in / accepted / unread.
    fn notification_counts<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<NotificationCounts, AppError>>;
}
```

#### `LockedMatch` (snapshot of a row inside a `FOR UPDATE` lock)

```rust
pub struct LockedMatch {
    pub user1_id: i32,
    pub user2_id: i32,
    pub status: String,
    pub offered_by: Option<i32>,
}
```

#### `MatchStatusSnapshot` (for status-change validation)

```rust
pub struct MatchStatusSnapshot {
    pub user1_id: i32,
    pub user2_id: i32,
    pub status: String,
    pub offered_by: Option<i32>,
    pub user1_applied: bool,
    pub user2_applied: bool,
}
```

### `InventoryRepository`

```rust
pub trait InventoryRepository: Send + Sync {
    fn upsert<'a>(
        &'a self,
        user_id: i32,
        merch_id: i32,
        status: &'a str,
        quantity: i32,
    ) -> RepositoryFuture<'a, Result<InventoryItem, AppError>>;

    fn list_for_user<'a>(
        &'a self,
        user_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<InventoryItem>, AppError>>;

    /// Used by the trade apply logic: TRADE row -> decrement, HAVE row -> upsert.
    /// Returns the (possibly new) inventory row.
    fn apply_trade_delta<'a>(
        &'a self,
        user_id: i32,
        merch_id: i32,
        delta_trade: i32,   // negative = decrement, 0 = skip
        delta_have: i32,    // positive = increment, 0 = skip
    ) -> RepositoryFuture<'a, Result<(), AppError>>;
}
```

### `MessageRepository`

```rust
pub trait MessageRepository: Send + Sync {
    fn list_for_match<'a>(
        &'a self,
        match_id: i32,
    ) -> RepositoryFuture<'a, Result<Vec<Message>, AppError>>;

    fn send<'a>(
        &'a self,
        match_id: i32,
        sender_id: i32,
        content: &'a str,
        message_type: Option<&'a str>,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> RepositoryFuture<'a, Result<Message, AppError>>;
}
```

## N+1 Fix Design

### Current (handlers/matches.rs:37-192)

```rust
let rows = ... SELECT all matches for user ...   // (1)
for row in rows {                                 // (N times)
    let other_user = ... SELECT user ...          // (2N)
    let haves = ... JOIN inventory ...             // (3N)
    let wants = ... JOIN inventory ...            // (4N)
    let selected_items = ... JOIN match_items ... (5N)
}
```
= 1 + 4N queries. For a user with 20 matches: 81 queries.

### New (`list_for_user` in MatchRepository)

```sql
-- Query 1: matches + other_user via a single JOIN
SELECT m.*, u.id AS other_id, u.username AS other_username
FROM matches m
JOIN users u ON u.id = (CASE WHEN m.user1_id = $1 THEN m.user2_id ELSE m.user1_id END)
WHERE (m.user1_id = $1 OR m.user2_id = $1) AND m.status != 'REJECTED'
ORDER BY m.created_at DESC;

-- Query 2: all potential haves for the user, batched by (user, peer, merch)
-- Returns 0 rows if there are no matches (early-return)
SELECT i.user_id, i.merch_id, i.quantity, m.name AS merch_name, m.photo_url
FROM inventory i
JOIN merchandise m ON m.id = i.merch_id
WHERE i.user_id = $1
  AND i.status = 'TRADE' AND i.quantity > 0
  AND EXISTS (SELECT 1 FROM inventory w WHERE w.user_id = ANY($match_user_ids) AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0);

-- Query 3: all selected items for all matches, batched
SELECT mi.*, m.name AS merch_name, m.photo_url
FROM match_items mi
JOIN merchandise m ON m.id = mi.merch_id
WHERE mi.match_id = ANY($match_ids);
```
= 3 queries total. For a user with 20 matches: 3 queries (27× faster).

The repository does the **in-memory join** between the 3 result sets using
`HashMap<match_id, Vec<X>>` lookups. This is fine because all three
result sets are bounded by the number of matches the user has.

## State Machine Model

The `MatchLifecycleService` is the only place the `Match` state machine
lives. It exposes 3 methods, each opening its own transaction:

```rust
pub struct MatchLifecycleService {
    pool: PgPool,
    matches: Arc<dyn MatchRepository>,
    inventory: Arc<dyn InventoryRepository>,
    // For phase 4 we keep raw pool access for transactions, but
    // composable repository methods for individual queries.
}

impl MatchLifecycleService {
    /// Transition PENDING -> OFFERED.
    /// Validates: match exists, status==PENDING, user is participant,
    /// at least one item offered. Inserts match_items, sets offered_by,
    /// status='OFFERED'. Atomic.
    pub async fn offer(
        &self,
        match_id: i32,
        offer: OfferTradeRequest,
    ) -> Result<(), AppError>;

    /// Validate state transitions; PENDING/OFFERED -> REJECTED,
    /// OFFERED -> ACCEPTED, ACCEPTED -> COMPLETED. Cascade-delete other
    /// PENDING matches on ACCEPT. Cascade-delete match_items on REJECT.
    pub async fn change_status(
        &self,
        match_id: i32,
        new_status: &str,
    ) -> Result<(), AppError>;

    /// Post-COMPLETED: apply the requesting user's inventory changes
    /// based on the match_items. Decrements TRADE for GIVE, increments
    /// HAVE for RECEIVE. Marks user{1,2}_inventory_applied_at.
    pub async fn apply_inventory(
        &self,
        match_id: i32,
        user_id: i32,
    ) -> Result<(), AppError>;
}
```

The service owns transactions because the state machine requires
multi-statement atomicity. We do **not** push transactions into the
repository (repositories stay single-statement).

## Handlers (thin)

`matches.rs` (507 → ~150 lines):

```rust
pub async fn list_all_matches(State(matches): State<Arc<dyn MatchRepository>>) -> ...;
pub async fn list_matches(State(matches): State<Arc<dyn MatchRepository>>, Path(user_id): Path<i32>) -> ...;
pub async fn offer_trade(State(s): State<AppState>, Path(match_id): Path<i32>, Json(req): Json<OfferTradeRequest>) -> ...;
pub async fn update_match_status(State(s): State<AppState>, Path(match_id): Path<i32>, Json(req): Json<UpdateMatchStatusRequest>) -> ...;
pub async fn apply_trade_inventory(State(s): State<AppState>, Path(match_id): Path<i32>, Json(req): Json<ApplyInventoryRequest>) -> ...;
pub async fn match_notification_counts(State(matches): State<Arc<dyn MatchRepository>>, Path(user_id): Path<i32>) -> ...;
```

`inventory.rs` (74 → ~30 lines):

```rust
pub async fn update_inventory(State(inv): State<Arc<dyn InventoryRepository>>, Json(req): Json<UpdateInventoryRequest>) -> ...;
pub async fn get_user_inventory(State(inv): State<Arc<dyn InventoryRepository>>, Path(user_id): Path<i32>) -> ...;
```

`messages.rs` (56 → ~25 lines):

```rust
pub async fn list_messages(State(msg): State<Arc<dyn MessageRepository>>, Path(match_id): Path<i32>) -> ...;
pub async fn send_message(State(msg): State<Arc<dyn MessageRepository>>, Path(match_id): Path<i32>, Json(req): Json<SendMessageRequest>) -> ...;
```

## Acceptance Criteria

1. `cargo test --test api_tests` — all 31 existing tests pass (no modifications)
2. `cargo test --lib` — new unit tests for:
   - `MatchRepository` mock
   - `InventoryRepository` mock
   - `MessageRepository` mock
   - `MatchLifecycleService` state machine (all 5 valid transitions + 4 invalid transitions)
3. `cargo clippy -- -D warnings` clean
4. `cargo fmt -- --check` clean
5. Total SQL in `src/handlers/{matches,inventory,messages}.rs` is zero
6. The N+1 fix is observable: a manual count of queries for a 20-match user drops from 81 to 3
7. `backend/src/matching.rs` (the background job) is **not** part of Phase 4 — left as a follow-up; it currently does its own raw SQL

## Risk Summary

- **High** for the lifecycle service. The match state machine is intricate (transactions, FOR UPDATE locks, cascade deletes, inventory arithmetic). The 405-line `test_trade_lifecycle_offer_accept_complete_apply` is the contract; it must continue to pass without modification.
- **Medium** for the N+1 fix. The 3-batch-query replacement is a behavior-equivalent rewrite of a heavily-trodden code path; the test suite exercises it through the offer + accept + apply flow.
- **Low** for `InventoryRepository` and `MessageRepository`. The existing handler logic is small and trivial to lift.

## Estimated Size

~1,000-1,500 LoC net change (most is the lifecycle service + N+1 helper code; ~150-200 LoC is new repository code; ~300 LoC is shrunken handler code).
