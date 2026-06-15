# Post-#191 Repository Layer: Concrete Structs + Generic Executor

## Status

The current shape of the repository layer, as established by the
**Phase A through Phase B-10** PR series (GitHub Issue #191, closed).

This document supersedes the older design notes that assumed a
`trait XxxRepository + struct PgXxxRepository + Arc<dyn XxxRepository>`
shape:

- [`refactoring_phase_4.md`](./refactoring_phase_4.md) — describes the
  initial Phase 4 shape, kept as a historical artifact (the
  `MatchLifecycleService` ownership of the multi-statement
  transactions is still current; the trait/dyn indirection is not)
- [`refactoring_plan.md`](./refactoring_plan.md) — the original Phase
  1-5 plan from #163, also kept as history

## Shape

Every domain aggregate has a single concrete struct that owns the
SQL for its table(s). There is no `dyn` indirection and no
`RepositoryFuture` boxed-future type alias. All methods are plain
`pub async fn` returning `Result<T, AppError>` directly.

```text
backend/src/repositories/
├── mod.rs                # module doc only (no type aliases)
├── event.rs              # EventRepository
├── event_favorites.rs    # EventFavoritesRepository
├── event_views.rs        # EventViewsRepository
├── group.rs              # MerchandiseGroupRepository
├── group_favorites.rs    # GroupFavoritesRepository
├── inventory.rs          # InventoryRepository
├── match_.rs             # MatchRepository
├── merch.rs              # MerchandiseRepository
├── message.rs            # MessageRepository
└── user.rs               # UserRepository
```

Each struct:

- Holds a `PgPool` for read paths and methods that own their own
  connection.
- Accepts a generic `E: Executor<'c, Database = Postgres>` parameter
  for the methods that participate in a caller-owned transaction.

## Method Signatures

### Read methods (use `&self.pool`)

```rust
impl MerchandiseRepository {
    pub async fn list_for_event(
        &self,
        event_id: i32,
        viewer_id: Option<i32>,
    ) -> Result<Vec<Merchandise>, AppError> { ... }
}
```

Plain `async fn`. Stored as `Arc<MerchandiseRepository>` in
`AppState` and shared with handlers and services via `State` /
constructor arguments.

### Transactional methods (take a generic Executor)

```rust
impl MatchRepository {
    pub async fn set_status<'c, E>(
        &self,
        exec: E,
        match_id: i32,
        new_status: &str,
    ) -> Result<(), AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    { ... }
}
```

The `Executor` trait is consumed by `.execute()`, so the method body
must use it exactly once. Two of the multi-statement methods were
refactored into single statements to satisfy this:

| Method | Refactor |
|---|---|
| `MatchRepository::insert_match_items` | N-row INSERT loop → `INSERT ... SELECT FROM UNNEST($2::int[], $4::text[], $5::int[])` bulk insert |
| `InventoryRepository::apply_trade_delta` | if-guarded pair of UPDATE + INSERT → single CTE with `WHERE $N > 0` short-circuit per branch |

The other transactional methods (`lock_for_update`, `set_status`,
`set_offered_by`, `delete_match_items`, `purge_other_pending`,
`mark_inventory_applied`) were already single-statement.

## Call Sites

The service opens a transaction and passes `&mut *tx` (a fresh
`&mut PgConnection` re-borrow per call) to each repo method:

```rust
let mut tx = self.pool.begin().await?;

self.matches
    .lock_for_update(&mut *tx, match_id)
    .await?
    .ok_or_else(|| AppError::not_found("Match not found"))?;

self.matches
    .set_status(&mut *tx, match_id, STATUS_OFFERED)
    .await?;

self.matches
    .set_offered_by(&mut *tx, match_id, offer.user_id)
    .await?;

self.matches
    .insert_match_items(&mut *tx, match_id, offer.user_id, &offer.items)
    .await?;

self.inventory
    .apply_trade_delta(&mut *tx, user_id, merch_id, delta_trade, delta_have)
    .await?;

tx.commit().await?;
```

`&mut *tx` derefs `Transaction` to `PgConnection` (via `DerefMut`).
`&mut PgConnection: Executor`, so the generic parameter is satisfied.
Each `&mut *tx` is a fresh re-borrow; NLL releases it at the end of
the await so the next call (or `tx.commit()`) works cleanly.

## AppState

`AppState` holds the repositories as concrete `Arc<...Repository>`,
not `Arc<dyn ...Repository>`:

```rust
pub struct AppState {
    pub pool: PgPool,
    pub users: Arc<UserRepository>,
    pub merch: Arc<MerchandiseRepository>,
    pub groups: Arc<MerchandiseGroupRepository>,
    pub matches: Arc<MatchRepository>,
    pub inventory: Arc<InventoryRepository>,
    pub messages: Arc<MessageRepository>,
    pub events: Arc<EventRepository>,
    pub event_favorites: Arc<EventFavoritesRepository>,
    pub event_views: Arc<EventViewsRepository>,
    pub group_favorites: Arc<GroupFavoritesRepository>,
    // ... + policy / merch_policy / match_lifecycle / storage / etc.
}
```

No `*_concrete` shadow fields, no `dyn` indirection in the state
shape.

## Testing

Two patterns, both backed by real PostgreSQL:

1. **Pure-logic methods** (e.g. `PermissionPolicy::require_role`,
   `require_owner_or_role`, `require_not_banned` — none of which
   touch the repo) use `PgPool::connect_lazy("postgres://localhost/dummy")`
   to construct a stub `Arc<UserRepository>` for the
   `PermissionPolicy::new` constructor. `connect_lazy` does not
   actually open a connection, so the URL just has to be syntactically
   valid. The test runs in microseconds.

2. **DB-backed methods** (e.g. `PermissionPolicy::verify`,
   `verify_active` — which call `users.get_verified` against the DB)
   use `#[sqlx::test]` which auto-provisions a fresh database per
   test and rolls it back. The test inserts the required `users` rows
   inline before the assertion.

The pre-#191 `MockUserRepository` (a hand-rolled in-memory fake that
the `PermissionPolicy` unit tests used) was removed in Phase B-8.
The 11 PermissionPolicy unit tests were rewritten to use the two
patterns above without losing coverage.

## Trade-offs (vs the old `trait + dyn` shape)

**Lost**:

- `Arc<dyn XxxRepository>`-based runtime mocking. The `MockUserRepository`
  was the only consumer, and it has been replaced by real DB pools.
- Test execution speed for the (now-removed) mock-using tests was
  faster (no DB roundtrip).

**Gained**:

- Compile time: dropped the `RepositoryFuture` boxed-future return
  type alias and the trait dispatch indirection.
- Argument passing in transactional code: the
  `self.matches.lock_for_update_conn(&mut *tx, match_id)` →
  `self.matches.lock_for_update(&mut *tx, match_id)` simplification
  drops the `_conn` suffix from 8 methods (7 on `MatchRepository` +
  1 on `InventoryRepository`) and makes the call-site intent
  immediately obvious.
- SQL ownership: all SQL for a table lives in one file. A schema
  change touches exactly one place per table.
- Service ↔ repository contract: the `Executor` parameter forces the
  caller to think about the tx ownership at the call site.

## PR Series (closed)

| PR | Phase | Repository | Net LoC |
|---|---|---|---|
| #192 | A | merch | -77 |
| #193 | B-1 | event_views | -13 |
| #194 | B-2 | event_favorites | -14 |
| #195 | B-3 | message | -25 |
| #196 | B-4 | group_favorites | -30 |
| #197 | B-5 | group | -51 |
| #198 | B-6 | inventory | -44 (B-6) + later amended in #201 |
| #199 | B-7 | event | -73 |
| #200 | B-8 | user | -214 (also drops `MockUserRepository`) |
| #201 | B-9 | match | -148 (also lifts `_conn` methods to generic `Executor`; bulk-INSERT + CTE refactors for the two multi-statement methods) |
| #210 | B-10 | mod.rs | -10 (drops the `RepositoryFuture` type alias and rewrites the module doc) |

**Total**: ~-700 LoC across 11 PRs, no behavior change, all 28
unit tests + 73 integration tests passing throughout.
