//! Repository layer for the ymatch backend.
//!
//! Each domain aggregate (User, Merchandise, Match, Event, etc.) has its own
//! submodule with:
//! - a `XxxRepository` trait (the abstract interface), and
//! - a `PgXxxRepository` struct (the concrete PostgreSQL implementation).
//!
//! The trait methods return [`RepositoryFuture`] so the trait is
//! `dyn`-compatible and can be stored as `Arc<dyn XxxRepository>` in the
//! router state. This mirrors the pattern used by [`crate::storage::ImageStorage`].
//!
//! Phase 2 of #163 introduces `UserRepository` first. Subsequent phases add
//! the rest.

use std::pin::Pin;

/// Future type returned by every `Repository` trait method.
///
/// `async fn` in traits is not `dyn`-compatible in edition 2024 without an
/// explicit boxed-future return. We keep the runtime backend selection
/// pattern (`Arc<dyn UserRepository>`) by returning a boxed future from
/// every method.
///
/// All `Repository` methods are `Send + 'static`-safe in practice: they
/// capture `&self` (which is `Send + Sync` because the trait bounds require
/// it) plus the input arguments.
pub type RepositoryFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

pub mod group;
pub mod inventory;
pub mod match_;
pub mod merch;
pub mod message;
pub mod user;
