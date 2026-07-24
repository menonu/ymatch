//! Match aggregate repository.
//!
//! [`MatchRepository`] owns the `matches` and `match_items` tables. It is
//! used by:
//!
//! - HTTP handlers (read-only paths: list, get, snapshot, items, counts)
//! - [`crate::services::match_lifecycle::MatchLifecycleService`]
//!   (transactional writes: offer, change_status, apply_inventory)
//! - [`crate::matching::run_matching_algorithm`] (small scan-step queries,
//!   PENDING insert, ADR 0012 rematch reopen)
//!
//! Phase 4 of #163 fixes the N+1 problem in the previous
//! `handlers::matches::list_matches` (1 + 4N queries for N matches) by
//! replacing it with [`MatchRepository::list_for_user`], which runs **4
//! queries total**: matches + other_user via JOIN, haves batched,
//! wants batched, match_items batched. The in-memory join happens
//! inside the repository.
//!
//! ## Transactional writes (Phase B-9 of #191)
//!
//! All 7 methods that participate in a transaction take a generic
//! `E: Executor<'c, Database = Postgres>` parameter. The caller passes
//! either `&self.pool` (a `&PgPool`, which is `Executor`), `&mut *tx`
//! from a `pool.begin()` block (a `&mut PgConnection`, also `Executor`),
//! or any other sqlx Executor.
//!
//! The Executor is consumed by `.execute()` so the method body must
//! use it exactly once. For [`MatchRepository::upsert_legs`] (#297) the
//! partial leg upsert runs as at most two statements (one upsert, one
//! delete of zero-quantity legs).
//!
//! Standard pattern in sqlx: the service opens the transaction
//! (`let mut tx = self.pool.begin().await?;`) and the repo methods are
//! passed `&mut *tx` (a fresh `&mut PgConnection` re-borrow each call).
//! NLL releases the reborrow at the end of each `await`, so the next
//! call (or `tx.commit()`) works cleanly.
//!
//! ## Module layout (#497)
//!
//! Split for cohesion — public API is still `MatchRepository` on this module:
//!
//! - [`read`] — list/get/counts/snapshot
//! - [`write`] — lifecycle writes (status, legs, delete, inventory applied)
//! - [`capacity`] — ADR 0010 mutual capacity + system cancel
//! - [`matcher`] — periodic matcher scan steps / insert / rematch

mod capacity;
mod matcher;
mod read;
mod write;

use crate::generated::ymatch::TradeMatch;
use crate::handlers::mappers::to_rfc3339;
use sqlx::{PgPool, Row};

/// Read-only snapshot of a match's status fields. Used by the lifecycle
/// service for the inventory-apply endpoint.
#[derive(Debug, Clone)]
pub struct MatchStatusSnapshot {
    pub user1_id: i32,
    pub user2_id: i32,
    pub status: String,
    pub offered_by: Option<i32>,
    /// ADR 0001: the group a match is scoped to. Both are NOT NULL on the
    /// table (see migration 20260629000000), so they are read as non-nullable.
    pub event_id: i32,
    pub group_name: String,
    pub user1_applied: bool,
    pub user2_applied: bool,
}

pub struct MatchRepository {
    pool: PgPool,
}

impl MatchRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

/// One WANT row that may seed a match ([`MatchRepository::list_matchable_wants`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MatchableWant {
    pub user_id: i32,
    pub merch_id: i32,
    pub event_id: i32,
    pub group_name: String,
}

/// Lightweight active-match row used for ADR 0010 capacity re-evaluation.
#[derive(Debug, Clone)]
pub struct ActiveMatchScope {
    pub id: i32,
    pub user1_id: i32,
    pub user2_id: i32,
    pub event_id: i32,
    pub group_name: String,
}

/// ADR 0010: cancel when either mutual capacity is zero (or negative).
/// Both sides positive (including unbalanced 2:1) keeps the match.
pub fn capacity_requires_cancel(cap1: i32, cap2: i32) -> bool {
    cap1 <= 0 || cap2 <= 0
}

/// Stable cancel reason code for SYSTEM message `content` (ADR 0010).
/// Display copy is localized on the client — do not store English prose.
pub const CANCEL_REASON_INVENTORY_CAPACITY: &str = "INVENTORY_CAPACITY";

/// Stable cancel reason code for SYSTEM message `content` (ADR 0008).
/// Display copy is localized on the client — do not store English prose.
pub const CANCEL_REASON_MERCH_DELETED: &str = "MERCH_DELETED";

/// Stable rematch reason codes for SYSTEM message `content` (ADR 0012 / #477).
/// Display copy is localized on the client — do not store English prose.
pub const REMATCH_REASON_AFTER_REJECTED: &str = "REMATCH_AFTER_REJECTED";
pub const REMATCH_REASON_AFTER_CANCELLED: &str = "REMATCH_AFTER_CANCELLED";

#[cfg(test)]
mod capacity_tests {
    use super::capacity_requires_cancel;

    #[test]
    fn keeps_when_both_positive_including_unbalanced() {
        assert!(!capacity_requires_cancel(2, 2));
        assert!(!capacity_requires_cancel(2, 1));
        assert!(!capacity_requires_cancel(1, 2));
        assert!(!capacity_requires_cancel(1, 1));
    }

    #[test]
    fn cancels_when_either_side_zero() {
        assert!(capacity_requires_cancel(2, 0));
        assert!(capacity_requires_cancel(0, 2));
        assert!(capacity_requires_cancel(1, 0));
        assert!(capacity_requires_cancel(0, 1));
        assert!(capacity_requires_cancel(0, 0));
    }

    #[test]
    fn cancels_when_negative_defensive() {
        assert!(capacity_requires_cancel(-1, 2));
        assert!(capacity_requires_cancel(2, -1));
    }
}

const MATCH_COLUMNS: &str = "id, user1_id, user2_id, status, offered_by, user1_inventory_applied_at, user2_inventory_applied_at, created_at, rematch_count, last_terminal_status, last_terminal_at";

fn match_status_snapshot_from_row(r: sqlx::postgres::PgRow) -> MatchStatusSnapshot {
    MatchStatusSnapshot {
        user1_id: r.get("user1_id"),
        user2_id: r.get("user2_id"),
        status: r.get("status"),
        offered_by: r.get("offered_by"),
        event_id: r.get("event_id"),
        group_name: r.get("group_name"),
        user1_applied: r
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("user1_inventory_applied_at")
            .is_some(),
        user2_applied: r
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("user2_inventory_applied_at")
            .is_some(),
    }
}

/// Helper: parse a `matches` row into a partial `TradeMatch` (no related data).
fn match_from_row(row: &sqlx::postgres::PgRow) -> TradeMatch {
    TradeMatch {
        id: row.get("id"),
        user1_id: row.get("user1_id"),
        user2_id: row.get("user2_id"),
        status: row.get("status"),
        created_at: to_rfc3339(row.get("created_at")),
        offered_by: row.get("offered_by"),
        inventory_applied: false,
        other_user: None,
        user_haves: vec![],
        user_wants: vec![],
        selected_items: vec![],
        // #322: populated by `list_for_user` (which joins events); None on the
        // admin `list_all` path (MATCH_COLUMNS does not select event/group).
        // #466: group_display_name also only filled on the list_for_user path.
        group_name: None,
        event_name: None,
        group_display_name: None,
        // ADR 0012 / #477: rematch annotation (defaults 0 / None on first match).
        rematch_count: row.get("rematch_count"),
        last_terminal_status: row.get("last_terminal_status"),
        last_terminal_at: to_rfc3339(row.get("last_terminal_at")),
    }
}
