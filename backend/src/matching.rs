//! Periodic matching algorithm.
//!
//! ## Layout (#497)
//!
//! - **Pure policy** (unit-tested here): [`is_group_matchable`],
//!   [`same_match_group`], [`existing_match_action`], [`rematch_reason_for`].
//! - **SQL** lives in [`MatchRepository`] as small named steps (one concern
//!   each) so filters can be changed without reading a mega-query.
//! - **This module** orchestrates the steps in plain nested loops that
//!   mirror the product narrative: WANT → TRADE partners → reciprocal
//!   TRADE/WANT in the same group → insert or rematch.
//!
//! ```text
//! for each matchable WANT (user A, merch X, group G):
//!   for each user B who TRADEs X:
//!     for each merch Y that A TRADEs in G:
//!       if B WANTs Y (live):
//!         ensure match for (A, B, G)   // insert | rematch | skip
//!         break  // one mutual edge is enough for this partner+group
//! ```

use crate::repositories::match_::{
    MatchRepository, REMATCH_REASON_AFTER_CANCELLED, REMATCH_REASON_AFTER_REJECTED,
};
use crate::repositories::user::UserRepository;
use sqlx::PgPool;

// ---------------------------------------------------------------------------
// Pure matching decisions (unit-tested)
//
// Policy mirrors of SQL filters (ADR 0001) and insert-vs-reopen (ADR 0012).
// SQL is the runtime source of truth; these helpers pin the rules cheaply.
// ---------------------------------------------------------------------------

/// ADR 0001: merchandise with a NULL or empty group is not matchable.
///
/// Mirrors matcher SQL: `group_name IS NOT NULL AND group_name <> ''`.
#[inline]
pub fn is_group_matchable(group_name: Option<&str>) -> bool {
    matches!(group_name, Some(g) if !g.is_empty())
}

/// Two rows share a matchable group only when both have the same non-null,
/// non-empty `(event_id, group_name)`.
#[inline]
pub fn same_match_group(
    event_a: i32,
    group_a: Option<&str>,
    event_b: i32,
    group_b: Option<&str>,
) -> bool {
    if !is_group_matchable(group_a) || !is_group_matchable(group_b) {
        return false;
    }
    event_a == event_b && group_a == group_b
}

/// How the matcher treats an existing match row for a rediscovered mutual
/// edge (same pair + group). ADR 0012: reopen terminal; never insert a
/// second row for active/COMPLETED.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExistingMatchAction {
    /// No row — insert a new PENDING match.
    Insert,
    /// REJECTED / CANCELLED — reopen the same id to PENDING.
    Reopen,
    /// Active (PENDING/OFFERED/ACCEPTED) or COMPLETED — leave alone.
    Skip,
}

/// Decide insert / reopen / skip for a rediscovered mutual edge.
///
/// `existing_status` is `None` when no row exists for the (pair, group).
pub fn existing_match_action(existing_status: Option<&str>) -> ExistingMatchAction {
    match existing_status {
        None => ExistingMatchAction::Insert,
        Some("REJECTED") | Some("CANCELLED") => ExistingMatchAction::Reopen,
        Some(_) => ExistingMatchAction::Skip,
    }
}

/// SYSTEM message reason when reopening a terminal match, if applicable.
pub fn rematch_reason_for(prior_status: &str) -> Option<&'static str> {
    match prior_status {
        "REJECTED" => Some(REMATCH_REASON_AFTER_REJECTED),
        "CANCELLED" => Some(REMATCH_REASON_AFTER_CANCELLED),
        _ => None,
    }
}

/// Run one matching pass.
///
/// Returns the number of PENDING rows newly created or reopened.
pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    let matches = MatchRepository::new(pool.clone());
    let users = UserRepository::new(pool.clone());
    let mut matches_created = 0;

    // 1. Seed: every eligible WANT (ordered for stable fairness).
    let wants = matches
        .list_matchable_wants()
        .await
        .map_err(|e| e.to_string())?;

    for want in wants {
        // 2. Who is TRADEing the merch this user wants?
        let partner_ids = matches
            .list_users_trading_merch(want.merch_id, want.user_id)
            .await
            .map_err(|e| e.to_string())?;

        for partner_id in partner_ids {
            // 3. What is the wanter TRADEing in this same group?
            //    (reciprocal inventory must be in-group — ADR 0001)
            let trade_merch_ids = matches
                .list_user_trade_merch_ids_in_group(want.user_id, want.event_id, &want.group_name)
                .await
                .map_err(|e| e.to_string())?;

            for trade_merch_id in trade_merch_ids {
                // 4. Does the partner WANT that trade merch (live)?
                let partner_wants = matches
                    .user_wants_live_merch(partner_id, trade_merch_id)
                    .await
                    .map_err(|e| e.to_string())?;
                if !partner_wants {
                    continue;
                }

                // Mutual edge found for (want.user_id, partner_id, group).
                if ensure_match_for_pair(
                    &matches,
                    &users,
                    want.user_id,
                    partner_id,
                    want.event_id,
                    &want.group_name,
                )
                .await?
                {
                    matches_created += 1;
                }
                // One mutual edge is enough for this partner+group.
                break;
            }
        }
    }

    Ok(matches_created)
}

/// Insert, rematch, or skip for one rediscovered (pair, group) edge.
///
/// Returns `true` when a new PENDING was created or a terminal row reopened.
async fn ensure_match_for_pair(
    matches: &MatchRepository,
    users: &UserRepository,
    user_a: i32,
    user_b: i32,
    event_id: i32,
    group_name: &str,
) -> Result<bool, String> {
    let existing = matches
        .find_for_pair_group(user_a, user_b, event_id, group_name)
        .await
        .map_err(|e| e.to_string())?;

    match existing_match_action(existing.as_ref().map(|(_, s)| s.as_str())) {
        ExistingMatchAction::Insert => {
            matches
                .insert_pending(user_a, user_b, event_id, group_name)
                .await
                .map_err(|e| e.to_string())?;
            notify_pair(users, user_a, user_b).await;
            Ok(true)
        }
        ExistingMatchAction::Reopen => {
            let Some((match_id, status)) = existing else {
                return Ok(false);
            };
            let Some(reason) = rematch_reason_for(&status) else {
                return Ok(false);
            };
            let reopened = matches
                .reopen_terminal(match_id, &status, reason)
                .await
                .map_err(|e| e.to_string())?;
            if reopened {
                notify_pair(users, user_a, user_b).await;
            }
            Ok(reopened)
        }
        ExistingMatchAction::Skip => Ok(false),
    }
}

async fn notify_pair(users: &UserRepository, user_a: i32, user_b: i32) {
    // Best-effort push. Missing user = vanished; other load errors logged (#266).
    let load = async |user_id: i32| match users.get_by_id(user_id).await {
        Ok(u) => u,
        Err(e) => {
            tracing::warn!(
                error = %e,
                user_id,
                "match notification: failed to load user"
            );
            None
        }
    };

    let u1 = load(user_a).await;
    let u2 = load(user_b).await;
    if let (Some(u1), Some(u2)) = (u1, u2) {
        if let Some(token) = u1.device_token.as_deref() {
            crate::notifications::send_match_notification(token, &u2.username).await;
        }
        if let Some(token) = u2.device_token.as_deref() {
            crate::notifications::send_match_notification(token, &u1.username).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- is_group_matchable (ADR 0001 null-group skip) ---

    #[test]
    fn null_group_is_not_matchable() {
        assert!(!is_group_matchable(None));
    }

    #[test]
    fn empty_group_is_not_matchable() {
        assert!(!is_group_matchable(Some("")));
    }

    #[test]
    fn named_group_is_matchable() {
        assert!(is_group_matchable(Some("Cards")));
        assert!(is_group_matchable(Some("G1")));
    }

    // --- same_match_group (group scoping) ---

    #[test]
    fn same_event_and_group_match() {
        assert!(same_match_group(1, Some("G"), 1, Some("G")));
    }

    #[test]
    fn different_group_same_event_do_not_match() {
        assert!(!same_match_group(1, Some("G1"), 1, Some("G2")));
    }

    #[test]
    fn same_group_name_different_event_do_not_match() {
        // group_name is only unique per event.
        assert!(!same_match_group(1, Some("Cards"), 2, Some("Cards")));
    }

    #[test]
    fn null_group_never_same_as_anything() {
        assert!(!same_match_group(1, None, 1, None));
        assert!(!same_match_group(1, None, 1, Some("G")));
        assert!(!same_match_group(1, Some("G"), 1, None));
    }

    // --- existing_match_action (dedup / rematch ADR 0012) ---

    #[test]
    fn no_existing_row_inserts() {
        assert_eq!(existing_match_action(None), ExistingMatchAction::Insert);
    }

    #[test]
    fn rejected_and_cancelled_reopen() {
        assert_eq!(
            existing_match_action(Some("REJECTED")),
            ExistingMatchAction::Reopen
        );
        assert_eq!(
            existing_match_action(Some("CANCELLED")),
            ExistingMatchAction::Reopen
        );
    }

    #[test]
    fn active_and_completed_skip() {
        for status in ["PENDING", "OFFERED", "ACCEPTED", "COMPLETED"] {
            assert_eq!(
                existing_match_action(Some(status)),
                ExistingMatchAction::Skip,
                "status {status} must skip"
            );
        }
    }

    #[test]
    fn unknown_status_skips_defensively() {
        assert_eq!(
            existing_match_action(Some("WEIRD")),
            ExistingMatchAction::Skip
        );
    }

    // --- rematch_reason_for ---

    #[test]
    fn rematch_reasons_for_terminal_only() {
        assert_eq!(
            rematch_reason_for("REJECTED"),
            Some(REMATCH_REASON_AFTER_REJECTED)
        );
        assert_eq!(
            rematch_reason_for("CANCELLED"),
            Some(REMATCH_REASON_AFTER_CANCELLED)
        );
        assert_eq!(rematch_reason_for("PENDING"), None);
        assert_eq!(rematch_reason_for("COMPLETED"), None);
        assert_eq!(rematch_reason_for(""), None);
    }
}
