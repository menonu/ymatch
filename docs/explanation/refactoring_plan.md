# Backend Refactoring Plan

## Status

Tracked by GitHub Issue [#163](https://github.com/menonu/ymatch/issues/163) (parent) and the per-phase sub-issues #164 - #168.

Last updated: 2026-06-09.

## Why

The ymatch Rust backend started as a single-developer prototype and has accreted responsibilities onto its HTTP handlers. As of 2026-06-09, the audit shows:

| Symptom | Count / Scope |
|---------|---------------|
| `sqlx::query*` call sites in `src/` | 96 |
| Handlers doing parse + validate + auth + DB + response | 41 (all of them) |
| `.map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?` repetitions | 71 |
| `StatusCode::INTERNAL_SERVER_ERROR` literal references in `src/handlers/` | 83 |
| `*_from_row` helper functions (file-private) | 3 |
| Tables touched in 3+ handler files | 8 / 11 |
| N+1 query patterns | 1 (`matches::list_matches`) |
| Duplicated soft-vs-hard-delete blocks | 2 |
| Custom error types / `IntoResponse` impls | 0 |
| Repository / DAO abstractions | 0 |
| Existing trait abstractions over IO | 1 (`ImageStorage`) |

This state blocks three things we want:

1. **Database migration** — moving from PostgreSQL to another SQL engine or to a document store would require touching ~30-50 SQL sites in handlers.
2. **Domain unit tests** — every test that exercises business logic currently requires a live PostgreSQL container.
3. **Refactor safety net** — the lack of a clean domain layer makes it hard to refactor the match lifecycle (the largest and most-fragile piece of the codebase) without breaking the production trade workflow.

## Goals (re-stated from #163)

1. **Modularization** — each domain (User, Merch, Match, Event, Group, Inventory, Message) gets its own submodule with a clear interface boundary.
2. **Cohesion** — SQL for a single table or aggregate lives in one place.
3. **Separation of concerns** — handlers do HTTP-shape translation; Repositories do data access; business logic (e.g., match state machine) lives in a service layer.
4. **Abstraction** — Repository traits over domain types; concrete `Pg*Repository` implementations; no SQL in handlers.
5. **Loose coupling** — handlers depend on `Arc<dyn FooRepository>`, not on `PgPool` directly.
6. **Centralized error type** — single `AppError` with `IntoResponse` implementation replaces the 71 ad-hoc tuples.

## Approach (Decided 2026-06-09)

- **Edition 2024 upgrade** as part of Phase 1 — enables native `async fn` in traits (no `#[async_trait]` macro needed).
- **Native async traits** in repositories — `Arc<dyn UserRepository>` is the State type handlers depend on.
- **Repository unit tests** (in-process mockable) added in each phase alongside integration tests. Mocking uses hand-rolled test doubles (no mockall dependency needed) since each Repository surface is small.
- **Existing `api_tests.rs` E2E** preserved as the contract test suite. It must remain green throughout.

## Non-Goals

- No change in API contract or HTTP behavior.
- No migration of production data.
- No new features.
- Issue #128 (group description UI) is paused; its backend work (PR #162) will be re-evaluated after the MerchandiseRepository lands in Phase 3.

## Architecture After Refactor

```
src/
├── main.rs                       # unchanged
├── lib.rs                        # re-exports modules
├── error.rs                      # NEW: AppError + IntoResponse
├── routes.rs                     # constructs Repositories and Services, wires them
├── storage/                      # unchanged in shape, drops #[async_trait]
│   ├── mod.rs                    # trait ImageStorage (native async fn)
│   ├── local.rs
│   └── firebase.rs
├── generated/                    # unchanged
│   └── ymatch.rs
├── repositories/                 # NEW: one file per aggregate
│   ├── mod.rs
│   ├── user.rs                   # trait UserRepository + PgUserRepository
│   ├── merch.rs
│   ├── group.rs
│   ├── match_.rs
│   ├── inventory.rs
│   ├── message.rs
│   ├── event.rs
│   ├── event_favorites.rs
│   ├── event_views.rs
│   └── group_favorites.rs
├── services/                     # NEW: business logic / policies
│   ├── mod.rs
│   ├── permissions.rs            # PermissionPolicy (consolidates handlers/permissions.rs)
│   └── match_lifecycle.rs        # match state machine (lifts code from matches.rs)
└── handlers/                     # THIN: parse -> service call -> response
    ├── mod.rs                    # exports
    ├── mappers.rs                # NEW: pub row mappers + datetime helpers
    ├── auth.rs
    ├── events.rs
    ├── merch.rs
    ├── groups.rs
    ├── matches.rs
    ├── inventory.rs
    ├── messages.rs
    ├── admin.rs
    ├── search.rs
    ├── images.rs
    └── system.rs
```

The handler `merch::create_merch` shrinks from ~67 LoC to roughly:

```rust
pub async fn create_merch(
    State(merch): State<Arc<dyn MerchandiseRepository>>,
    State(groups): State<Arc<dyn MerchandiseGroupRepository>>,
    State(policy): State<Arc<PermissionPolicy>>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, AppError> {
    if let Some(creator_id) = payload.creator_id {
        let user = policy.verify(creator_id).await?;
        policy.require_not_banned(&user)?;
    }
    let merch = merch.create(event_id, payload).await?;
    Ok(Json(merch))
}
```

## Phase Plan (5 PRs)

| # | Issue | Scope | Approx. LoC | Status |
|---|-------|-------|-------------|--------|
| 1 | [#164](https://github.com/menonu/ymatch/issues/164) | Edition 2024 + AppError + RowMapper + drop async-trait | 300-500 | not started |
| 2 | [#165](https://github.com/menonu/ymatch/issues/165) | UserRepository + PermissionPolicy | 400-700 | not started |
| 3 | [#166](https://github.com/menonu/ymatch/issues/166) | MerchandiseRepository + MerchandiseGroupRepository (absorb PR #162) | 500-800 | not started |
| 4 | [#167](https://github.com/menonu/ymatch/issues/167) | MatchRepository + InventoryRepository + MessageRepository (N+1 fix) | 700-1000 | not started |
| 5 | [#168](https://github.com/menonu/ymatch/issues/168) | Event/EventFavorites/EventViews/GroupFavorites | 400-600 | not started |

Each phase ends with a green test suite and a `cargo clippy -- -D warnings` / `cargo fmt -- --check` run. Each phase is independently mergeable; rolling back means reverting one PR.

## Common Acceptance Criteria (per phase)

1. `cargo test` — all 31 existing integration tests pass without modification.
2. New unit tests for the new Repository / Service / Error surface.
3. `cargo clippy -- -D warnings` clean.
4. `cargo fmt -- --check` clean.
5. The diff of the affected handler shrinks monotonically: more SQL leaves the handler each phase.
6. The aggregate LoC of SQL inside `src/handlers/*.rs` strictly decreases each phase.

## Risk Summary

| Phase | Risk | Why | Mitigation |
|-------|------|-----|------------|
| 1 | Low-Medium | Mechanical `.map_err` removal | Existing 31-test suite |
| 2 | Low | User table is well-isolated; permission logic is centralized | Existing tests + new unit tests for PermissionPolicy |
| 3 | Medium | Soft-vs-hard delete branch + dynamic UPDATE builder | Existing tests (incl. the 4 from #128) |
| 4 | **High** | Match lifecycle is intricate (transactions, FOR UPDATE locks, cascade deletes, inventory arithmetic) | The 405-line `test_trade_lifecycle_*` test is the contract |
| 5 | Low | Event tables are touched less; the 3-subquery list is the only complex piece | Keep the SQL as-is, just move it |

## Relation to Existing Work

- The audit transcript (tool_eacbdb6d5001DQSN5Ec1a3gHSJ) is the source of truth for the counts above. It is referenced from #163.
- The `ImageStorage` trait in `src/storage/mod.rs` is the *only* existing good model of an IO abstraction in this codebase. The Repository pattern will mirror its shape (trait + two impls, swapped via env var / State).
- PR #162 (group description backend) is paused; it will be re-applied on top of Phase 3, or its commits will be reworked into the MerchandiseGroupRepository PR.
