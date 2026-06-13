//! Match lifecycle service.
//!
//! [`MatchLifecycleService`] owns the multi-statement transactions for
//! the match state machine. Repositories are single-statement; this
//! service is the only place we open `pool.begin()`.
//!
//! State machine:
//!
//! ```text
//!     PENDING ──offer──> OFFERED
//!     PENDING ──reject──> REJECTED  (also: OFFERED ──reject──> REJECTED)
//!     OFFERED ──accept──> ACCEPTED
//!     ACCEPTED ──complete──> COMPLETED
//! ```
//!
//! The apply-inventory step runs *after* COMPLETED and updates the
//! `inventory` table based on the offer's `match_items` rows. Each side
//! applies independently; the per-user flag (`user{1,2}_inventory_applied_at`)
//! prevents double-application.

use crate::error::AppError;
use crate::generated::ymatch::OfferTradeRequest;
use crate::repositories::inventory::InventoryRepository;
use crate::repositories::match_::MatchRepository;
use sqlx::PgPool;
use std::sync::Arc;

const STATUS_PENDING: &str = "PENDING";
const STATUS_OFFERED: &str = "OFFERED";
const STATUS_ACCEPTED: &str = "ACCEPTED";
const STATUS_COMPLETED: &str = "COMPLETED";
const STATUS_REJECTED: &str = "REJECTED";

/// Service for the match state machine.
///
/// Holds concrete `Arc<MatchRepository>` and
/// `Arc<InventoryRepository>` (not `dyn`). The repository
/// transactional methods take a `&mut PgConnection` so we can
/// reuse one transaction across multiple repository calls by
/// passing `&mut *tx` (the standard sqlx pattern).
#[derive(Clone)]
pub struct MatchLifecycleService {
    pool: PgPool,
    matches: Arc<MatchRepository>,
    inventory: Arc<InventoryRepository>,
}

impl MatchLifecycleService {
    pub fn new(
        pool: PgPool,
        matches: Arc<MatchRepository>,
        inventory: Arc<InventoryRepository>,
    ) -> Self {
        Self {
            pool,
            matches,
            inventory,
        }
    }

    /// Transition PENDING -> OFFERED.
    ///
    /// Validates: match exists, status==PENDING, user is one of the two
    /// participants, payload contains at least one item. Inserts each
    /// `match_items` row, sets `offered_by` and `status='OFFERED'`.
    /// Atomic.
    ///
    /// The SQL lives in `MatchRepository` (the `_conn` methods) so the
    /// repository owns the `matches` and `match_items` tables. This
    /// service is the orchestrator: open a tx, call the repo
    /// methods with `&mut *tx`, commit. Drop the `tx` and the
    /// rollback happens automatically.
    pub async fn offer(&self, match_id: i32, offer: OfferTradeRequest) -> Result<(), AppError> {
        if offer.items.is_empty() {
            return Err(AppError::bad_request("Must select at least one item"));
        }

        let mut tx = self.pool.begin().await?;

        let locked = self
            .matches
            .lock_for_update(&mut tx, match_id)
            .await?
            .ok_or_else(|| AppError::not_found("Match not found"))?;

        if locked.status != STATUS_PENDING {
            return Err(AppError::bad_request("Can only offer on PENDING matches"));
        }
        if offer.user_id != locked.user1_id && offer.user_id != locked.user2_id {
            return Err(AppError::forbidden("Not part of this match"));
        }

        self.matches
            .insert_match_items(&mut tx, match_id, offer.user_id, &offer.items)
            .await?;
        self.matches
            .set_status(&mut tx, match_id, STATUS_OFFERED)
            .await?;
        self.matches
            .set_offered_by(&mut tx, match_id, offer.user_id)
            .await?;

        tx.commit().await?;
        Ok(())
    }

    /// Validate a state transition and apply it. Possible transitions:
    ///
    /// - PENDING/OFFERED -> REJECTED  (cascades to delete match_items)
    /// - OFFERED         -> ACCEPTED  (cascades to delete other PENDING matches)
    /// - ACCEPTED        -> COMPLETED
    pub async fn change_status(&self, match_id: i32, new_status: &str) -> Result<(), AppError> {
        let valid = matches!(new_status, "ACCEPTED" | "REJECTED" | "COMPLETED");
        if !valid {
            return Err(AppError::bad_request("Invalid status"));
        }

        let mut tx = self.pool.begin().await?;

        let locked = self
            .matches
            .lock_for_update(&mut tx, match_id)
            .await?
            .ok_or_else(|| AppError::not_found("Match not found"))?;

        match (new_status, locked.status.as_str()) {
            ("ACCEPTED", s) if s != STATUS_OFFERED => {
                return Err(AppError::bad_request("Can only accept OFFERED matches"));
            }
            ("COMPLETED", s) if s != STATUS_ACCEPTED => {
                return Err(AppError::bad_request("Can only complete ACCEPTED matches"));
            }
            ("REJECTED", s) if s != STATUS_PENDING && s != STATUS_OFFERED => {
                return Err(AppError::bad_request(
                    "Can only reject PENDING or OFFERED matches",
                ));
            }
            _ => {}
        }

        self.matches
            .set_status(&mut tx, match_id, new_status)
            .await?;

        if new_status == STATUS_ACCEPTED {
            // Purge other PENDING matches between the same pair.
            self.matches
                .purge_other_pending(&mut tx, match_id, locked.user1_id, locked.user2_id)
                .await?;
        }

        if new_status == STATUS_REJECTED {
            self.matches.delete_match_items(&mut tx, match_id).await?;
        }

        tx.commit().await?;
        Ok(())
    }

    /// Apply the requesting user's inventory changes for a COMPLETED
    /// match. Each side applies independently; the per-user flag
    /// (`user{1,2}_inventory_applied_at`) prevents double-application.
    ///
    /// The state machine logic for `apply_inventory` is small and
    /// pure enough to unit test in isolation
    /// (`apply_inventory_delta`); the transaction-bearing part is
    /// covered by the integration test
    /// `test_trade_lifecycle_offer_accept_complete_apply`.
    pub async fn apply_inventory(&self, match_id: i32, user_id: i32) -> Result<(), AppError> {
        let snapshot = self
            .matches
            .get_status_snapshot(match_id)
            .await?
            .ok_or_else(|| AppError::not_found("Match not found"))?;

        if snapshot.status != STATUS_COMPLETED {
            return Err(AppError::bad_request(
                "Can only apply inventory on COMPLETED matches",
            ));
        }
        if user_id != snapshot.user1_id && user_id != snapshot.user2_id {
            return Err(AppError::forbidden("Not part of this match"));
        }

        let is_user1 = user_id == snapshot.user1_id;
        if is_user1 && snapshot.user1_applied {
            return Err(AppError::conflict(
                "Inventory already applied for this user",
            ));
        }
        if !is_user1 && snapshot.user2_applied {
            return Err(AppError::conflict(
                "Inventory already applied for this user",
            ));
        }

        let offered_by = snapshot.offered_by.unwrap_or(snapshot.user1_id);
        let requesting_is_offerer = user_id == offered_by;

        let items = self.matches.list_match_items(match_id).await?;

        // Open a single transaction so the inventory writes and the
        // per-user applied flag are atomic. If we crash between the
        // deltas and the flag, the next retry sees
        // `user{1,2}_inventory_applied_at IS NOT NULL` and refuses to
        // re-apply.
        let mut tx = self.pool.begin().await?;

        for item in &items {
            // Items stored from offerer's perspective:
            //   GIVE = offerer gives, other receives
            //   RECEIVE = offerer receives, other gives
            //
            // For the requesting user:
            //   - if they are the offerer:
            //       GIVE    -> decrement own TRADE
            //       RECEIVE -> increment own HAVE
            //   - if they are the other (non-offerer):
            //       GIVE    -> increment own HAVE (they received the offerer's item)
            //       RECEIVE -> decrement own TRADE (they gave this item)
            let (delta_trade, delta_have) =
                apply_inventory_delta(&item.direction, requesting_is_offerer, item.quantity);
            if delta_trade == 0 && delta_have == 0 {
                continue;
            }
            self.inventory
                .apply_trade_delta_conn(tx.as_mut(), user_id, item.merch_id, delta_trade, delta_have)
                .await?;
        }

        self.matches
            .mark_inventory_applied(&mut tx, match_id, is_user1)
            .await?;

        tx.commit().await?;
        Ok(())
    }
}

// Note: the lifecycle service requires a real database (transactions are
// the core of correctness). The state machine logic for
// `apply_inventory` is small and pure enough to unit test in isolation.
// The transaction-bearing methods (offer, change_status) are covered by
// the integration test suite in backend/tests/api_tests.rs.

/// Map `(direction, requesting_is_offerer) -> (delta_trade, delta_have)`.
///
/// This is the same logic that `apply_inventory` uses, factored out as a
/// pure function so it can be unit-tested without a database.
fn apply_inventory_delta(
    direction: &str,
    requesting_is_offerer: bool,
    quantity: i32,
) -> (i32, i32) {
    if requesting_is_offerer {
        match direction {
            "GIVE" => (quantity, 0),
            "RECEIVE" => (0, quantity),
            _ => (0, 0),
        }
    } else {
        match direction {
            "GIVE" => (0, quantity),
            "RECEIVE" => (quantity, 0),
            _ => (0, 0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::apply_inventory_delta;

    #[test]
    fn offerer_give_decrements_own_trade() {
        assert_eq!(apply_inventory_delta("GIVE", true, 3), (3, 0));
    }

    #[test]
    fn offerer_receive_increments_own_have() {
        assert_eq!(apply_inventory_delta("RECEIVE", true, 5), (0, 5));
    }

    #[test]
    fn other_give_increments_own_have() {
        assert_eq!(apply_inventory_delta("GIVE", false, 2), (0, 2));
    }

    #[test]
    fn other_receive_decrements_own_trade() {
        assert_eq!(apply_inventory_delta("RECEIVE", false, 4), (4, 0));
    }

    #[test]
    fn unknown_direction_is_noop() {
        assert_eq!(apply_inventory_delta("FOO", true, 1), (0, 0));
        assert_eq!(apply_inventory_delta("FOO", false, 1), (0, 0));
    }
}
