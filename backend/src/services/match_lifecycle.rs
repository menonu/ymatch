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
use crate::repositories::match_::{MatchRepository, MatchStatusSnapshot};
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
            .lock_for_update(&mut *tx, match_id)
            .await?
            .ok_or_else(|| AppError::not_found("Match not found"))?;

        validate_offer_transition(&offer, &locked)?;

        // Issue #294: cap offered quantities by the receiving side's WANT
        // quantity. GIVE is capped by the *other* participant's want;
        // RECEIVE is capped by the *offerer's* own want.
        let merch_ids: Vec<i32> = offer.items.iter().map(|i| i.merch_id).collect();
        let other_id = if offer.user_id == locked.user1_id {
            locked.user2_id
        } else {
            locked.user1_id
        };
        let offerer_wants = self
            .inventory
            .want_quantities(&mut *tx, offer.user_id, &merch_ids)
            .await?;
        let other_wants = self
            .inventory
            .want_quantities(&mut *tx, other_id, &merch_ids)
            .await?;
        validate_offer_quantities(&offer, &offerer_wants, &other_wants)?;

        self.matches
            .insert_match_items(&mut *tx, match_id, offer.user_id, &offer.items)
            .await?;
        self.matches
            .set_status(&mut *tx, match_id, STATUS_OFFERED)
            .await?;
        self.matches
            .set_offered_by(&mut *tx, match_id, offer.user_id)
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
        validate_transition_target(new_status)?;

        let mut tx = self.pool.begin().await?;

        let locked = self
            .matches
            .lock_for_update(&mut *tx, match_id)
            .await?
            .ok_or_else(|| AppError::not_found("Match not found"))?;

        validate_status_transition(new_status, &locked.status)?;

        self.matches
            .set_status(&mut *tx, match_id, new_status)
            .await?;

        if new_status == STATUS_ACCEPTED {
            // Purge other PENDING matches between the same pair.
            self.matches
                .purge_other_pending(&mut *tx, match_id, locked.user1_id, locked.user2_id)
                .await?;
        }

        if new_status == STATUS_REJECTED {
            self.matches.delete_match_items(&mut *tx, match_id).await?;
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
                .apply_trade_delta(&mut *tx, user_id, item.merch_id, delta_trade, delta_have)
                .await?;
        }

        self.matches
            .mark_inventory_applied(&mut *tx, match_id, is_user1)
            .await?;

        tx.commit().await?;
        Ok(())
    }
}

// Note: the lifecycle service requires a real database (transactions are
// the core of correctness), so the transaction-bearing parts of
// `offer`, `change_status`, and `apply_inventory` are covered by the
// integration test suite in backend/tests/api_tests.rs. The pure
// state-machine guards are factored out below (`validate_offer_transition`,
// `validate_transition_target`, `validate_status_transition`) and
// `apply_inventory_delta` so they can be unit-tested without a database.

/// Validate that each offered item's quantity is within the matched/wanted
/// quantity on the receiving side.
///
/// Factored out of [`MatchLifecycleService::offer`] so the cap can be
/// unit-tested without a database. The caller resolves the want-quantity
/// maps from the inventory table and passes them in:
///
/// - `offerer_wants` — the offerer's WANT quantities, keyed by merch_id.
///   Caps RECEIVE items (the offerer receives, so the offerer must want at
///   least that many).
/// - `other_wants` — the other participant's WANT quantities, keyed by
///   merch_id. Caps GIVE items (the offerer gives, so the other side must
///   want at least that many).
///
/// Quantities are aggregated per `(direction, merch_id)` so a caller cannot
/// bypass the cap by splitting one over-quota item into several rows.
fn validate_offer_quantities(
    offer: &OfferTradeRequest,
    offerer_wants: &std::collections::HashMap<i32, i32>,
    other_wants: &std::collections::HashMap<i32, i32>,
) -> Result<(), AppError> {
    let mut give_totals: std::collections::HashMap<i32, i32> = std::collections::HashMap::new();
    let mut recv_totals: std::collections::HashMap<i32, i32> = std::collections::HashMap::new();
    for item in &offer.items {
        if item.quantity <= 0 {
            return Err(AppError::bad_request("Offer quantity must be positive"));
        }
        match item.direction.as_str() {
            "GIVE" => *give_totals.entry(item.merch_id).or_insert(0) += item.quantity,
            "RECEIVE" => *recv_totals.entry(item.merch_id).or_insert(0) += item.quantity,
            other => {
                return Err(AppError::bad_request(format!("Invalid direction: {other}")));
            }
        }
    }
    for (merch_id, total) in &give_totals {
        let cap = other_wants.get(merch_id).copied().unwrap_or(0);
        if *total > cap {
            return Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity",
            ));
        }
    }
    for (merch_id, total) in &recv_totals {
        let cap = offerer_wants.get(merch_id).copied().unwrap_or(0);
        if *total > cap {
            return Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity",
            ));
        }
    }
    Ok(())
}

/// Validate the PENDING -> OFFERED transition against the locked match.
///
/// Factored out of [`MatchLifecycleService::offer`] so the state-machine
/// guards can be unit-tested without a database. Assumes the caller has
/// already resolved the not-found case (the match exists) and checked the
/// payload is non-empty (that check stays before opening the transaction).
fn validate_offer_transition(
    offer: &OfferTradeRequest,
    locked: &MatchStatusSnapshot,
) -> Result<(), AppError> {
    if locked.status != STATUS_PENDING {
        return Err(AppError::bad_request("Can only offer on PENDING matches"));
    }
    if offer.user_id != locked.user1_id && offer.user_id != locked.user2_id {
        return Err(AppError::forbidden("Not part of this match"));
    }
    Ok(())
}

/// Reject transition targets that are not part of the state machine.
///
/// Factored out of [`MatchLifecycleService::change_status`] so it can be
/// unit-tested. Called *before* opening the transaction so an invalid
/// target short-circuits before any DB work — and before the not-found
/// check (an invalid status on a missing match id must still be a 400, not
/// a 404; see `test_update_match_status_validation`).
fn validate_transition_target(new_status: &str) -> Result<(), AppError> {
    if !matches!(new_status, "ACCEPTED" | "REJECTED" | "COMPLETED") {
        return Err(AppError::bad_request("Invalid status"));
    }
    Ok(())
}

/// Validate a status transition against the match's current status.
///
/// Factored out of [`MatchLifecycleService::change_status`] so the
/// state-machine guards can be unit-tested without a database. Assumes the
/// target is already known-valid (see [`validate_transition_target`]).
fn validate_status_transition(new_status: &str, current_status: &str) -> Result<(), AppError> {
    match (new_status, current_status) {
        ("ACCEPTED", s) if s != STATUS_OFFERED => {
            Err(AppError::bad_request("Can only accept OFFERED matches"))
        }
        ("COMPLETED", s) if s != STATUS_ACCEPTED => {
            Err(AppError::bad_request("Can only complete ACCEPTED matches"))
        }
        ("REJECTED", s) if s != STATUS_PENDING && s != STATUS_OFFERED => Err(
            AppError::bad_request("Can only reject PENDING or OFFERED matches"),
        ),
        _ => Ok(()),
    }
}

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
    use super::*;
    use crate::generated::ymatch::OfferItem;

    /// Build a `MatchStatusSnapshot` with only the fields the guards read.
    fn snapshot(status: &str, user1: i32, user2: i32) -> MatchStatusSnapshot {
        MatchStatusSnapshot {
            user1_id: user1,
            user2_id: user2,
            status: status.to_string(),
            offered_by: None,
            user1_applied: false,
            user2_applied: false,
        }
    }

    /// Build an `OfferTradeRequest` for `user_id` with a single dummy item.
    /// The guards under test don't inspect items, so one placeholder suffices.
    fn offer(user_id: i32) -> OfferTradeRequest {
        OfferTradeRequest {
            user_id,
            items: vec![OfferItem {
                merch_id: 1,
                direction: "GIVE".into(),
                quantity: 1,
            }],
        }
    }

    // --- apply_inventory_delta ---

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

    // --- validate_offer_quantities (want-quantity cap) ---

    fn want_map(entries: &[(i32, i32)]) -> std::collections::HashMap<i32, i32> {
        entries.iter().copied().collect()
    }

    fn offer_qty(user_id: i32, items: &[(i32, &str, i32)]) -> OfferTradeRequest {
        OfferTradeRequest {
            user_id,
            items: items
                .iter()
                .map(|(merch_id, direction, quantity)| OfferItem {
                    merch_id: *merch_id,
                    direction: (*direction).to_string(),
                    quantity: *quantity,
                })
                .collect(),
        }
    }

    #[test]
    fn give_within_other_want_ok() {
        // Offerer gives merch 1 x2; other side wants merch 1 x2.
        let offer = offer_qty(1, &[(1, "GIVE", 2)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[]), &want_map(&[(1, 2)])),
            Ok(())
        );
    }

    #[test]
    fn give_exceeding_other_want_rejected() {
        // Offerer gives merch 1 x3; other side only wants x2.
        let offer = offer_qty(1, &[(1, "GIVE", 3)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[]), &want_map(&[(1, 2)])),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn give_with_no_matching_want_rejected() {
        // Offerer gives merch 1 x1; other side does not want it at all.
        let offer = offer_qty(1, &[(1, "GIVE", 1)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[]), &want_map(&[])),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn receive_within_offerer_want_ok() {
        // Offerer receives merch 2 x1; offerer wants merch 2 x1.
        let offer = offer_qty(1, &[(2, "RECEIVE", 1)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[(2, 1)]), &want_map(&[])),
            Ok(())
        );
    }

    #[test]
    fn receive_exceeding_offerer_want_rejected() {
        // Offerer receives merch 2 x2; offerer only wants x1.
        let offer = offer_qty(1, &[(2, "RECEIVE", 2)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[(2, 1)]), &want_map(&[])),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn split_items_cannot_bypass_cap() {
        // Two GIVE rows of merch 1 x1 each; other side wants only x1.
        // Aggregation must catch the 2-total exceeding the 1-cap.
        let offer = offer_qty(1, &[(1, "GIVE", 1), (1, "GIVE", 1)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[]), &want_map(&[(1, 1)])),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn non_positive_quantity_rejected() {
        let offer = offer_qty(1, &[(1, "GIVE", 0)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[]), &want_map(&[(1, 1)])),
            Err(AppError::bad_request("Offer quantity must be positive"))
        );
    }

    #[test]
    fn invalid_direction_rejected() {
        let offer = offer_qty(1, &[(1, "TRADE", 1)]);
        assert!(validate_offer_quantities(&offer, &want_map(&[]), &want_map(&[(1, 1)])).is_err());
    }

    #[test]
    fn mixed_directions_each_capped_independently() {
        // GIVE merch 1 x1 (other wants 1) + RECEIVE merch 2 x2 (offerer wants 1).
        let offer = offer_qty(1, &[(1, "GIVE", 1), (2, "RECEIVE", 2)]);
        assert_eq!(
            validate_offer_quantities(&offer, &want_map(&[(2, 1)]), &want_map(&[(1, 1)])),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    // --- validate_offer_transition (PENDING -> OFFERED) ---

    #[test]
    fn offer_on_non_pending_rejected() {
        // Status is checked before participation, so a participant offering
        // on a non-PENDING match still gets the status error.
        assert_eq!(
            validate_offer_transition(&offer(1), &snapshot("OFFERED", 1, 2)),
            Err(AppError::bad_request("Can only offer on PENDING matches"))
        );
    }

    #[test]
    fn offer_on_completed_rejected() {
        assert_eq!(
            validate_offer_transition(&offer(1), &snapshot("COMPLETED", 1, 2)),
            Err(AppError::bad_request("Can only offer on PENDING matches"))
        );
    }

    #[test]
    fn offer_by_non_participant_forbidden() {
        assert_eq!(
            validate_offer_transition(&offer(3), &snapshot("PENDING", 1, 2)),
            Err(AppError::forbidden("Not part of this match"))
        );
    }

    #[test]
    fn offer_by_user1_on_pending_ok() {
        assert_eq!(
            validate_offer_transition(&offer(1), &snapshot("PENDING", 1, 2)),
            Ok(())
        );
    }

    #[test]
    fn offer_by_user2_on_pending_ok() {
        assert_eq!(
            validate_offer_transition(&offer(2), &snapshot("PENDING", 1, 2)),
            Ok(())
        );
    }

    // --- validate_transition_target ---

    #[test]
    fn transition_target_pending_rejected() {
        // PENDING is a source state, not a valid transition target.
        assert_eq!(
            validate_transition_target("PENDING"),
            Err(AppError::bad_request("Invalid status"))
        );
    }

    #[test]
    fn transition_target_unknown_rejected() {
        assert_eq!(
            validate_transition_target("FOO"),
            Err(AppError::bad_request("Invalid status"))
        );
    }

    #[test]
    fn transition_target_empty_rejected() {
        assert_eq!(
            validate_transition_target(""),
            Err(AppError::bad_request("Invalid status"))
        );
    }

    #[test]
    fn transition_target_accepted_ok() {
        assert_eq!(validate_transition_target("ACCEPTED"), Ok(()));
    }

    #[test]
    fn transition_target_rejected_ok() {
        assert_eq!(validate_transition_target("REJECTED"), Ok(()));
    }

    #[test]
    fn transition_target_completed_ok() {
        assert_eq!(validate_transition_target("COMPLETED"), Ok(()));
    }

    // --- validate_status_transition (the four-arm guard) ---

    #[test]
    fn accept_from_pending_rejected() {
        assert_eq!(
            validate_status_transition("ACCEPTED", "PENDING"),
            Err(AppError::bad_request("Can only accept OFFERED matches"))
        );
    }

    #[test]
    fn accept_from_offered_ok() {
        assert_eq!(validate_status_transition("ACCEPTED", "OFFERED"), Ok(()));
    }

    #[test]
    fn complete_from_offered_rejected() {
        assert_eq!(
            validate_status_transition("COMPLETED", "OFFERED"),
            Err(AppError::bad_request("Can only complete ACCEPTED matches"))
        );
    }

    #[test]
    fn complete_from_accepted_ok() {
        assert_eq!(validate_status_transition("COMPLETED", "ACCEPTED"), Ok(()));
    }

    #[test]
    fn reject_from_pending_ok() {
        assert_eq!(validate_status_transition("REJECTED", "PENDING"), Ok(()));
    }

    #[test]
    fn reject_from_offered_ok() {
        assert_eq!(validate_status_transition("REJECTED", "OFFERED"), Ok(()));
    }

    #[test]
    fn reject_from_accepted_rejected() {
        assert_eq!(
            validate_status_transition("REJECTED", "ACCEPTED"),
            Err(AppError::bad_request(
                "Can only reject PENDING or OFFERED matches"
            ))
        );
    }

    // Remaining valid-target / invalid-source pairs that fall into the arms
    // above but weren't asserted directly — pins the full table.

    #[test]
    fn accept_from_completed_rejected() {
        assert_eq!(
            validate_status_transition("ACCEPTED", "COMPLETED"),
            Err(AppError::bad_request("Can only accept OFFERED matches"))
        );
    }

    #[test]
    fn complete_from_pending_rejected() {
        assert_eq!(
            validate_status_transition("COMPLETED", "PENDING"),
            Err(AppError::bad_request("Can only complete ACCEPTED matches"))
        );
    }

    #[test]
    fn reject_from_completed_rejected() {
        assert_eq!(
            validate_status_transition("REJECTED", "COMPLETED"),
            Err(AppError::bad_request(
                "Can only reject PENDING or OFFERED matches"
            ))
        );
    }
}
