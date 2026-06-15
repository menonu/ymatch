# Backend Refactor Summary (Issue #163)

## Status

**Completed 2026-06-12.** All 5 phases of the Repository pattern refactor
are merged to `main`. The parent issue (#163) and the 5 phase sub-issues
(#164-#168) are closed.

## TL;DR

The ymatch backend started as a single-developer prototype and
accreted responsibilities onto HTTP handlers. After this refactor, all
SQL for application tables is concentrated in 11 thin Repository
traits + their sqlx implementations, all authorization logic lives in 3
service-layer policies, and the `src/handlers/*.rs` files are pure
parse-and-delegate.

> **Post-#163 follow-up (Issue #191, also closed)**: the
> `trait + Pg*Repository + Arc<dyn ...>` shape that #163 produced was
> refined into a single **concrete struct + generic Executor** form
> via PRs #192 - #210. The `dyn` indirection, the
> `RepositoryFuture<'a, T> = Pin<Box<dyn Future + Send + 'a>>` boxed
> future type alias, and the `_conn` suffix on the 8 transactional
> methods were all removed. The SQL ownership and the
> `MatchLifecycleService` orchestration are unchanged from the
> #163-era design. The post-#191 shape was documented on
> [GitHub Issue #191](https://github.com/menonu/ymatch/issues/191)
> (the closing comment).

## Phase Recap

| Phase | PR | LoC (handler → repo+service) | Key Wins |
|-------|----|------------------------------|----------|
| 1 — Edition 2024 + AppError + mappers | #169 | handlers: -71 (.map_err sites); error.rs +116; mappers.rs +116 | Edition upgrade enables native async fn in traits. Central error type eliminates 71 `.map_err` repetitions. |
| 2 — UserRepository + PermissionPolicy | #170 | handlers: -65; repositories/user.rs +505; services/permissions.rs +217 | All `users` table access through the trait. `verify / require_not_banned / require_role / require_owner_or_role` centralized. |
| 3 — MerchandiseRepository + MerchandiseGroupRepository | #171 | handlers: -56; repositories/merch.rs +431; repositories/group.rs +211; services/merch_permissions.rs +63 | `merchandise_groups` table + 4 tests **absorbed PR #162**. Soft-vs-hard delete decision lives in exactly one method. |
| 4 — Match/Inventory/Message + MatchLifecycleService | #172 | handlers: -470 (matches 507→79, inventory 74→31, messages 56→34); repositories/ +634; services/match_lifecycle.rs +344 | **N+1 fix**: `list_matches` 1+4N → 4 queries (20× faster on 20-match user). State machine + 4 transactions in one service. |
| 5 — Event/EventFavorites/EventViews/GroupFavorites | #175 | handlers: -134; repositories/ +615 | All event/favorite/view SQL lifted. Search uses `EventRepository::search`. |

## Final Architecture

```
backend/src/
├── lib.rs
├── main.rs
├── routes.rs                # AppState + FromRef impls
├── error.rs                 # AppError + IntoResponse
├── handlers/                # PURE parse-and-delegate (1105 LoC total)
│   ├── mod.rs
│   ├── mappers.rs           # Shared row→struct mappers
│   ├── auth.rs
│   ├── events.rs            # 156 LoC
│   ├── groups.rs            # 78 LoC
│   ├── merch.rs             # 137 LoC
│   ├── matches.rs           # 79 LoC (was 507)
│   ├── inventory.rs         # 31 LoC (was 74)
│   ├── messages.rs          # 34 LoC (was 56)
│   ├── images.rs            # 74 LoC
│   ├── search.rs            # 79 LoC
│   ├── admin.rs             # 162 LoC
│   └── system.rs            # 26 LoC
├── repositories/            # SQL concentrated here (2861 LoC)
│   ├── mod.rs               # RepositoryFuture type alias
│   ├── user.rs              # UserRepository (12 methods)
│   ├── merch.rs             # MerchandiseRepository (8 methods)
│   ├── group.rs             # MerchandiseGroupRepository (5 methods)
│   ├── match_.rs            # MatchRepository (5 methods, N+1 fixed)
│   ├── inventory.rs         # InventoryRepository (2 methods)
│   ├── message.rs           # MessageRepository (2 methods)
│   ├── event.rs             # EventRepository (8 methods)
│   ├── event_favorites.rs   # EventFavoritesRepository (1 method)
│   ├── event_views.rs       # EventViewsRepository (1 method)
│   └── group_favorites.rs   # GroupFavoritesRepository (2 methods)
├── services/                # Cross-cutting business logic (634 LoC)
│   ├── mod.rs
│   ├── permissions.rs       # PermissionPolicy (Phase 2)
│   ├── merch_permissions.rs # MerchPermissionPolicy (Phase 3, 3-way rule)
│   └── match_lifecycle.rs   # MatchLifecycleService (Phase 4, state machine)
├── storage/                 # ImageStorage (Phase 1, pre-existing)
│   ├── mod.rs
│   ├── local.rs
│   └── firebase.rs
├── matching.rs              # Background job (raw SQL; out of scope #163)
├── notifications.rs         # Stub
└── generated/               # prost-generated proto types
    ├── mod.rs
    └── ymatch.rs
```

## Aggregate Numbers

| Metric | Before | After |
|--------|-------:|------:|
| `sqlx::query*` call sites in `src/handlers/` | ~75 | 0 (modulo admin `delete_merch_by_id`/`delete_match` 1-line queries documented) |
| `.map_err(|e| (StatusCode, e.to_string()))` sites | 71 | 0 (single `?` works via `From<sqlx::Error>`) |
| Files with `handlers::permissions::*` direct calls | 5 | 0 |
| Handler functions doing parse + validate + auth + DB + response | 41 | 0 (now pure parse + delegate) |
| Duplicated soft-vs-hard delete logic (merch handler + admin handler) | 2 copies | 1 method (`MerchandiseRepository::delete_merch`) |
| `SELECT creator_id FROM ...` repeated verbatim | 4 sites | 0 (consolidated into `*Repository::get_creator`) |
| N+1 in `list_matches` | 1+4N queries | 4 queries total |

## What `cargo test` says

- **29 unit tests** (was 12 before refactor):
  - 7 AppError status-mapping
  - 2 mapper helpers
  - 9 PermissionPolicy
  - 1 verified_user smoke
  - 5 apply_inventory_delta
  - 5 other (storage smoke)
- **31 integration tests** in `backend/tests/api_tests.rs` — **unchanged** through the entire refactor. They are the contract that all 5 phases respect.

## Risks Acknowledged

- **#174** (Repository tx-aware variants) — `MatchLifecycleService` keeps
  transactional SQL inline because trait methods cannot easily accept
  `&mut sqlx::Transaction` while remaining dyn-compatible. This is a
  follow-up cleanup, not a blocker.
- **`backend/src/matching.rs`** (background job) still has its own raw
  SQL. Documented in `docs/explanation/refactoring_phase_4.md` as a
  follow-up.
- **`MerchandiseRepository::delete_merch`** takes `(event_id, merch_id)`.
  The admin path does 1 extra `SELECT event_id FROM merchandise` query
  to bridge. A future `delete_by_id(merch_id)` would eliminate it.

## How to Use This Pattern for Future Tables

When adding a new domain table:

1. **Create a `XxxRepository` trait** in `backend/src/repositories/xxx.rs`.
   Use `RepositoryFuture<'a, Result<T, AppError>>` return type and the
   `BoxFuture`-style for dyn-compatibility.
2. **Implement `PgXxxRepository`** in the same file. SQL stays here.
3. **Add a `FromRef<AppState> for Arc<dyn XxxRepository>` impl** in
   `routes.rs`.
4. **Construct it in `create_router`** and add it to `AppState`.
5. **Handlers are thin**: `State(state): State<AppState>`, call
   `state.xxx.method().await?`, wrap in `Json` / `StatusCode`.
6. **Permission checks** go through `state.policy` (always) and
   `state.merch_policy` (for merch-specific rules). New domain-specific
   3-way rules get a new `services/xxx_permissions.rs`.
7. **Transactional state machines** (like MatchLifecycleService) own
   their own `pool.begin()` blocks and call repository methods that
   are single-statement.

## Relation to Other Issues

- **#128** (group description UI) — backend portion was absorbed by
  Phase 3 (#171). Frontend work remains paused. Once #128 frontend
  resumes, no further backend work is required.
- **#173** — Phase 4 follow-up (Medium/Low items from the PR #172
  review). Small optimizations, not part of the core refactor.
- **#174** — Repository tx-aware variants. The largest known
  follow-up. A separate post-#163 cleanup.

## References

- Plan: `docs/explanation/refactoring_plan.md`
- Phase 4 design: `docs/explanation/refactoring_phase_4.md`
- Parent issue: #163 (closed 2026-06-12)
- Phase issues: #164, #165, #166, #167, #168 (all closed)
- Phase PRs: #169, #170, #171, #172, #175 (all merged)
EOF
