//! Repository layer for the ymatch backend.
//!
//! Each domain aggregate (User, Merchandise, Match, Event, Group, ...)
//! has its own submodule with a single `XxxRepository` struct that owns
//! the SQL for the corresponding table(s). All structs hold a `PgPool`
//! for read paths and accept a generic `E: Executor<'c, Database =
//! Postgres>` parameter for the methods that participate in a
//! transaction.
//!
//! ## Migration history (Phase A through B-9 of #191)
//!
//! The early shape of this layer was `trait XxxRepository + struct
//! PgXxxRepository + Arc<dyn XxxRepository>` for dyn-compatibility (so
//! repositories could be swapped at runtime / mocked in unit tests).
//! That required every trait method to return
//! `RepositoryFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>`
//! because `async fn` in traits is not dyn-compatible in edition 2024
//! without an explicit boxed-future return.
//!
//! The migration to concrete structs (see #191) dropped the trait
//! indirection and the `dyn` usage entirely, which also removed the
//! need for the boxed-future type alias. The remaining struct methods
//! are plain `pub async fn` returning `Result<T, AppError>` directly.
//! Transactional methods take a generic `E: Executor<'c, Database =
//! Postgres>` parameter (the multi-statement ones were refactored to
//! single statements — UNNEST bulk insert for `match_items`, CTE for
//! `apply_trade_delta` — so the executor is consumed exactly once per
//! call).
//!
//! Tests use real DB pools via `#[sqlx::test]` (auto-rollback per
//! test) or `PgPool::connect_lazy` (for pure-logic tests that never
//! touch the DB). The `MockUserRepository` previously used by
//! `PermissionPolicy` tests was removed in Phase B-8.

pub mod event;
pub mod event_favorites;
pub mod event_views;
pub mod group;
pub mod group_favorites;
pub mod inventory;
pub mod match_;
pub mod merch;
pub mod message;
pub mod user;
