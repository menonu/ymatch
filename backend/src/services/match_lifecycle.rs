//! Match lifecycle service.
//!
//! [`MatchLifecycleService`] owns the multi-statement transactions for
//! the match state machine. Repositories are single-statement; this
//! service is the only place we open `pool.begin()`.
//!
//! State machine (#297 negotiation):
//!
//! ```text
//!     PENDING ──propose──> OFFERED ──counter──> OFFERED ── …
//!        │                   │
//!        │                   ├─accept (non-proposer + balanced)──> ACCEPTED
//!        │                   └─reject──────────────────────────> REJECTED
//!        └──reject──> REJECTED
//!     ACCEPTED ──complete──> COMPLETED
//! ```
//!
//! `OFFERED` is the "proposal on the table" state; `offered_by` is the last
//! proposer. Either participant may open from PENDING; only the non-proposer
//! may counter-offer from OFFERED. Legs accumulate by partial upsert
//! (unspecified legs persist). Accept is the non-proposer's and requires a
//! balanced proposal (Σ qty each side gives equal and > 0).
//!
//! The apply-inventory step runs *after* COMPLETED and updates the
//! `inventory` table based on the offer's `match_items` legs. Each side
//! applies independently; the per-user flag (`user{1,2}_inventory_applied_at`)
//! prevents double-application.

use crate::error::AppError;
use crate::generated::ymatch::{OfferItem, OfferTradeRequest};
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

    /// Submit or counter-offer a proposal (#297).
    ///
    /// A proposal is a set of absolute legs `(giver_user_id, merch_id,
    /// quantity)`. From PENDING, either participant may open. From OFFERED,
    /// only the non-proposer may counter-offer. Legs are upserted partially
    /// (unspecified legs persist; `quantity == 0` removes a leg), so a
    /// counter can add only its own give/receive to move toward balance.
    ///
    /// Validates: match exists; transition is legal (`validate_propose_transition`);
    /// each leg's giver is a participant, quantity >= 0, and the resulting
    /// quantity per `(giver, merch)` does not exceed the receiver's WANT
    /// quantity (`validate_legs`). Then upserts legs, sets `offered_by` to
    /// the proposer and `status='OFFERED'`. Atomic.
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

        validate_propose_transition(
            &locked.status,
            offer.user_id,
            locked.user1_id,
            locked.user2_id,
            locked.offered_by,
        )?;

        // Issue #294/#297: cap each leg's quantity by the receiver's WANT
        // quantity. The receiver of a leg is the non-giver, so we need both
        // participants' want quantities.
        let merch_ids: Vec<i32> = offer.items.iter().map(|i| i.merch_id).collect();
        let user1_wants = self
            .inventory
            .want_quantities(&mut *tx, locked.user1_id, &merch_ids)
            .await?;
        let user2_wants = self
            .inventory
            .want_quantities(&mut *tx, locked.user2_id, &merch_ids)
            .await?;
        validate_legs(
            &offer.items,
            locked.user1_id,
            locked.user2_id,
            &user1_wants,
            &user2_wants,
        )?;

        self.matches
            .upsert_legs(&mut *tx, match_id, &offer.items)
            .await?;
        self.matches
            .remove_legs(&mut *tx, match_id, &offer.items)
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
    /// - OFFERED         -> ACCEPTED  (non-proposer + balanced only; purges
    ///   other PENDING matches between the same pair)
    /// - ACCEPTED        -> COMPLETED
    ///
    /// `user_id` is the acting user (carried by `UpdateMatchStatusRequest`
    /// since #297); `validate_participation` closes the previous authz gap
    /// where `change_status` ignored who was calling.
    pub async fn change_status(
        &self,
        match_id: i32,
        user_id: i32,
        new_status: &str,
    ) -> Result<(), AppError> {
        validate_transition_target(new_status)?;

        let mut tx = self.pool.begin().await?;

        let locked = self
            .matches
            .lock_for_update(&mut *tx, match_id)
            .await?
            .ok_or_else(|| AppError::not_found("Match not found"))?;

        validate_participation(user_id, locked.user1_id, locked.user2_id)?;
        validate_status_transition(new_status, &locked.status)?;

        if new_status == STATUS_ACCEPTED {
            // Accept is the non-proposer's, and only of a balanced proposal.
            let proposer = locked.offered_by.unwrap_or(locked.user1_id);
            if user_id == proposer {
                return Err(AppError::bad_request("Cannot accept your own proposal"));
            }
            let items = self.matches.list_match_items(match_id).await?;
            let legs: Vec<(i32, i32)> = items
                .iter()
                .map(|i| (i.giver_user_id, i.quantity))
                .collect();
            if !is_balanced(&legs, locked.user1_id, locked.user2_id) {
                return Err(AppError::bad_request(
                    "Cannot accept an unbalanced proposal",
                ));
            }
            self.matches
                .set_status(&mut *tx, match_id, new_status)
                .await?;
            // Purge other PENDING matches between the same pair.
            self.matches
                .purge_other_pending(&mut *tx, match_id, locked.user1_id, locked.user2_id)
                .await?;
        } else {
            self.matches
                .set_status(&mut *tx, match_id, new_status)
                .await?;
            if new_status == STATUS_REJECTED {
                self.matches.delete_match_items(&mut *tx, match_id).await?;
            }
        }

        tx.commit().await?;
        Ok(())
    }

    /// Apply the requesting user's inventory changes for a COMPLETED
    /// match. Each side applies independently; the per-user flag
    /// (`user{1,2}_inventory_applied_at`) prevents double-application.
    ///
    /// Legs are absolute (#297): for each leg `(giver, merch, qty)`, the
    /// giver's TRADE decreases by qty and the receiver's HAVE increases by
    /// qty. The pure side selection lives in [`apply_inventory_delta`] (so it
    /// can be unit-tested without a database); the transaction-bearing part
    /// is covered by the integration test
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

        let items = self.matches.list_match_items(match_id).await?;

        // Open a single transaction so the inventory writes and the
        // per-user applied flag are atomic. If we crash between the
        // deltas and the flag, the next retry sees
        // `user{1,2}_inventory_applied_at IS NOT NULL` and refuses to
        // re-apply.
        let mut tx = self.pool.begin().await?;

        for item in &items {
            // Absolute leg (#297): giver gives qty of merch to the receiver.
            //   requesting == giver    -> decrement own TRADE
            //   requesting == receiver -> increment own HAVE
            let (delta_trade, delta_have) =
                apply_inventory_delta(item.giver_user_id, user_id, item.quantity);
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
// state-machine guards are factored out below (`validate_propose_transition`,
// `validate_participation`, `validate_legs`, `is_balanced`,
// `validate_transition_target`, `validate_status_transition`,
// `apply_inventory_delta`) so they can be unit-tested without a database.

/// Validate that the proposed legs are well-formed and within the receiver's
/// WANT quantity (#294/#297).
///
/// Each leg is `(giver_user_id, merch_id, quantity)`; the receiver is the
/// non-giver, so the cap is the non-giver's WANT of that merch. `quantity`
/// may be 0 (remove the leg); negative is rejected. Quantities are
/// aggregated per `(giver, merch_id)` so a caller cannot bypass the cap by
/// splitting one over-quota leg into several rows. `user1_wants` /
/// `user2_wants` are the two participants' WANT maps keyed by merch_id.
fn validate_legs(
    items: &[OfferItem],
    user1_id: i32,
    user2_id: i32,
    user1_wants: &std::collections::HashMap<i32, i32>,
    user2_wants: &std::collections::HashMap<i32, i32>,
) -> Result<(), AppError> {
    // giver -> merch_id -> aggregated qty (positive legs only)
    let mut totals: std::collections::HashMap<i32, std::collections::HashMap<i32, i32>> =
        std::collections::HashMap::new();
    for item in items {
        if item.giver_user_id != user1_id && item.giver_user_id != user2_id {
            return Err(AppError::bad_request("Invalid leg giver"));
        }
        if item.quantity < 0 {
            return Err(AppError::bad_request("Offer quantity must not be negative"));
        }
        if item.quantity > 0 {
            *totals
                .entry(item.giver_user_id)
                .or_default()
                .entry(item.merch_id)
                .or_insert(0) += item.quantity;
        }
    }
    for (giver, merch_totals) in &totals {
        let non_giver = if *giver == user1_id {
            user2_id
        } else {
            user1_id
        };
        let wants = if non_giver == user1_id {
            user1_wants
        } else {
            user2_wants
        };
        for (merch_id, total) in merch_totals {
            let cap = wants.get(merch_id).copied().unwrap_or(0);
            if *total > cap {
                return Err(AppError::bad_request(
                    "Offered quantity exceeds the matched/wanted quantity",
                ));
            }
        }
    }
    Ok(())
}

/// Whether the proposal's legs balance: the total quantity each side gives
/// is equal AND at least one side gives something (so a 0:0 / empty proposal
/// is not "balanced" and cannot be accepted). `legs` is `(giver_user_id,
/// quantity)` per leg.
fn is_balanced(legs: &[(i32, i32)], user1_id: i32, user2_id: i32) -> bool {
    let mut u1 = 0;
    let mut u2 = 0;
    for (giver, qty) in legs {
        if *giver == user1_id {
            u1 += qty;
        } else if *giver == user2_id {
            u2 += qty;
        }
    }
    u1 == u2 && u1 > 0
}

/// Validate that a propose/counter-offer transition is legal (#297).
///
/// From PENDING either participant may open. From OFFERED only the
/// non-proposer may counter-offer (the proposer must wait for a response).
/// The caller has already resolved the not-found case; the non-empty-payload
/// check stays before opening the transaction.
fn validate_propose_transition(
    status: &str,
    user_id: i32,
    user1_id: i32,
    user2_id: i32,
    offered_by: Option<i32>,
) -> Result<(), AppError> {
    if user_id != user1_id && user_id != user2_id {
        return Err(AppError::forbidden("Not part of this match"));
    }
    match status {
        STATUS_PENDING => Ok(()),
        STATUS_OFFERED => {
            let proposer = offered_by.unwrap_or(user1_id);
            if user_id == proposer {
                Err(AppError::bad_request(
                    "Cannot counter your own proposal; wait for a response",
                ))
            } else {
                Ok(())
            }
        }
        _ => Err(AppError::bad_request(
            "Can only propose on PENDING or OFFERED matches",
        )),
    }
}

/// Validate that the acting user is one of the match's two participants.
fn validate_participation(user_id: i32, user1_id: i32, user2_id: i32) -> Result<(), AppError> {
    if user_id != user1_id && user_id != user2_id {
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

/// Map `(giver_id, requesting_user_id, quantity) -> (delta_trade, delta_have)`.
///
/// Absolute legs (#297): the giver's TRADE decreases by qty and the
/// receiver's HAVE increases by qty. For the requesting user, return the
/// side that applies to them: if they are the giver → `(qty, 0)` (their
/// TRADE decreases); if they are the receiver → `(0, qty)` (their HAVE
/// increases). Factored out as a pure function so it can be unit-tested
/// without a database.
fn apply_inventory_delta(giver_id: i32, requesting_user_id: i32, quantity: i32) -> (i32, i32) {
    if giver_id == requesting_user_id {
        (quantity, 0)
    } else {
        (0, quantity)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::generated::ymatch::OfferItem;

    fn want_map(entries: &[(i32, i32)]) -> std::collections::HashMap<i32, i32> {
        entries.iter().copied().collect()
    }

    /// Build a leg list `(giver_user_id, merch_id, quantity)` for `validate_legs`.
    fn legs(items: &[(i32, i32, i32)]) -> Vec<OfferItem> {
        items
            .iter()
            .map(|(giver, merch, qty)| OfferItem {
                merch_id: *merch,
                giver_user_id: *giver,
                quantity: *qty,
            })
            .collect()
    }

    // --- apply_inventory_delta (giver-absolute, #297) ---

    #[test]
    fn giver_is_requester_decrements_own_trade() {
        // Requesting user is the giver: their TRADE decreases by qty.
        assert_eq!(apply_inventory_delta(1, 1, 3), (3, 0));
    }

    #[test]
    fn receiver_increments_own_have() {
        // Requesting user is the receiver: their HAVE increases by qty.
        assert_eq!(apply_inventory_delta(2, 1, 5), (0, 5));
    }

    #[test]
    fn zero_quantity_is_noop() {
        assert_eq!(apply_inventory_delta(1, 1, 0), (0, 0));
        assert_eq!(apply_inventory_delta(2, 1, 0), (0, 0));
    }

    // --- validate_legs (want-quantity cap, giver model) ---

    #[test]
    fn give_leg_within_receiver_want_ok() {
        // giver=1 gives merch 1 x2; receiver=2 wants merch 1 x2.
        assert_eq!(
            validate_legs(
                &legs(&[(1, 1, 2)]),
                1,
                2,
                &want_map(&[]),
                &want_map(&[(1, 2)])
            ),
            Ok(())
        );
    }

    #[test]
    fn give_leg_exceeds_receiver_want_rejected() {
        // giver=1 gives merch 1 x3; receiver=2 only wants x2.
        assert_eq!(
            validate_legs(
                &legs(&[(1, 1, 3)]),
                1,
                2,
                &want_map(&[]),
                &want_map(&[(1, 2)])
            ),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn receive_leg_capped_by_requester_want() {
        // giver=2 gives merch 2 (= user1 receives); receiver=1 wants merch 2 x1.
        // qty 1 ok, qty 2 rejected.
        assert_eq!(
            validate_legs(
                &legs(&[(2, 2, 1)]),
                1,
                2,
                &want_map(&[(2, 1)]),
                &want_map(&[])
            ),
            Ok(())
        );
        assert_eq!(
            validate_legs(
                &legs(&[(2, 2, 2)]),
                1,
                2,
                &want_map(&[(2, 1)]),
                &want_map(&[])
            ),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn split_legs_cannot_bypass_cap() {
        // Two legs (giver=1, merch=1, qty=1); receiver=2 wants only x1.
        assert_eq!(
            validate_legs(
                &legs(&[(1, 1, 1), (1, 1, 1)]),
                1,
                2,
                &want_map(&[]),
                &want_map(&[(1, 1)])
            ),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    #[test]
    fn negative_quantity_rejected() {
        assert_eq!(
            validate_legs(
                &legs(&[(1, 1, -1)]),
                1,
                2,
                &want_map(&[]),
                &want_map(&[(1, 1)])
            ),
            Err(AppError::bad_request("Offer quantity must not be negative"))
        );
    }

    #[test]
    fn invalid_giver_rejected() {
        // giver=3 is not a participant.
        assert_eq!(
            validate_legs(
                &legs(&[(3, 1, 1)]),
                1,
                2,
                &want_map(&[]),
                &want_map(&[(1, 1)])
            ),
            Err(AppError::bad_request("Invalid leg giver"))
        );
    }

    #[test]
    fn zero_quantity_leg_allowed_no_cap_check() {
        // qty 0 = remove; no want is required for a removal.
        assert_eq!(
            validate_legs(&legs(&[(1, 1, 0)]), 1, 2, &want_map(&[]), &want_map(&[])),
            Ok(())
        );
    }

    #[test]
    fn each_side_capped_independently() {
        // giver=1 gives merch 1 x1 (receiver 2 wants 1 → ok);
        // giver=2 gives merch 2 x2 (receiver 1 wants 1 → reject).
        assert_eq!(
            validate_legs(
                &legs(&[(1, 1, 1), (2, 2, 2)]),
                1,
                2,
                &want_map(&[(2, 1)]),
                &want_map(&[(1, 1)])
            ),
            Err(AppError::bad_request(
                "Offered quantity exceeds the matched/wanted quantity"
            ))
        );
    }

    // --- is_balanced ---

    #[test]
    fn balanced_when_equal_totals() {
        // u1 gives 2, u2 gives 2 → balanced.
        assert!(is_balanced(&[(1, 2), (2, 2)], 1, 2));
    }

    #[test]
    fn unbalanced_when_totals_differ() {
        assert!(!is_balanced(&[(1, 3), (2, 2)], 1, 2));
    }

    #[test]
    fn balanced_across_different_merch() {
        // u1 gives 1 of merch A + 1 of merch B (total 2); u2 gives 2 of merch C.
        assert!(is_balanced(&[(1, 1), (1, 1), (2, 2)], 1, 2));
    }

    #[test]
    fn empty_proposal_not_balanced() {
        // 0:0 is not a trade.
        assert!(!is_balanced(&[], 1, 2));
    }

    // --- validate_propose_transition (PENDING open / OFFERED counter) ---

    #[test]
    fn propose_open_on_pending_by_either_participant_ok() {
        assert_eq!(
            validate_propose_transition(STATUS_PENDING, 1, 1, 2, None),
            Ok(())
        );
        assert_eq!(
            validate_propose_transition(STATUS_PENDING, 2, 1, 2, None),
            Ok(())
        );
    }

    #[test]
    fn counter_on_offered_by_non_proposer_ok() {
        // offered_by=1 (proposer); user 2 counters.
        assert_eq!(
            validate_propose_transition(STATUS_OFFERED, 2, 1, 2, Some(1)),
            Ok(())
        );
    }

    #[test]
    fn counter_on_offered_by_proposer_rejected() {
        // offered_by=1; user 1 cannot counter their own proposal.
        assert_eq!(
            validate_propose_transition(STATUS_OFFERED, 1, 1, 2, Some(1)),
            Err(AppError::bad_request(
                "Cannot counter your own proposal; wait for a response"
            ))
        );
    }

    #[test]
    fn propose_by_non_participant_forbidden() {
        assert_eq!(
            validate_propose_transition(STATUS_PENDING, 3, 1, 2, None),
            Err(AppError::forbidden("Not part of this match"))
        );
    }

    #[test]
    fn propose_on_completed_rejected() {
        assert_eq!(
            validate_propose_transition(STATUS_COMPLETED, 1, 1, 2, None),
            Err(AppError::bad_request(
                "Can only propose on PENDING or OFFERED matches"
            ))
        );
    }

    // --- validate_participation ---

    #[test]
    fn participation_ok_for_either_user() {
        assert_eq!(validate_participation(1, 1, 2), Ok(()));
        assert_eq!(validate_participation(2, 1, 2), Ok(()));
    }

    #[test]
    fn participation_rejected_for_outsider() {
        assert_eq!(
            validate_participation(3, 1, 2),
            Err(AppError::forbidden("Not part of this match"))
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
