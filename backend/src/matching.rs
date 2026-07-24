//! Periodic matching algorithm.
//!
//! Pure policy helpers ([`is_group_matchable`], [`same_match_group`],
//! [`existing_match_action`], [`rematch_reason_for`]) are unit-tested here.
//! Domain SQL lives in [`MatchRepository`] (set-based mutual-edge discovery,
//! PENDING insert, ADR 0012 rematch reopen). The job loop only decides
//! insert/reopen/skip and fires notifications (#497).

use crate::repositories::match_::{
    MatchRepository, REMATCH_REASON_AFTER_CANCELLED, REMATCH_REASON_AFTER_REJECTED,
};
use crate::repositories::user::UserRepository;
use sqlx::PgPool;

// ---------------------------------------------------------------------------
// Pure matching decisions (unit-tested)
//
// `existing_match_action` / `rematch_reason_for` gate the insert-vs-reopen
// branch inside `run_matching_algorithm`. `is_group_matchable` /
// `same_match_group` are policy mirrors of the discovery SQL filters
// (ADR 0001) so group-scoping edges stay cheap to pin without a DB.
// ---------------------------------------------------------------------------

/// ADR 0001: merchandise with a NULL or empty group is not matchable.
///
/// Mirrors the matcher discovery SQL (`group_name IS NOT NULL AND group_name <> ''`).
#[inline]
pub fn is_group_matchable(group_name: Option<&str>) -> bool {
    matches!(group_name, Some(g) if !g.is_empty())
}

/// Two merchandise rows share a matchable group identity only when both have
/// the same non-null, non-empty `(event_id, group_name)`. Policy mirror of the
/// SQL join on `(event_id, group_name)` after the null/empty filter.
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

/// How the matcher should treat an existing match row for a rediscovered
/// mutual edge (same pair + group). ADR 0012: reopen terminal rows; never
/// insert a second row for active/COMPLETED.
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
/// Used by `run_matching_algorithm` on the existing-row branch.
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

/// Run one matching pass: discover mutual edges, then insert or rematch.
///
/// Returns the number of new PENDING rows created or reopened.
pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    let matches = MatchRepository::new(pool.clone());
    let users = UserRepository::new(pool.clone());

    let edges = matches
        .discover_mutual_edges()
        .await
        .map_err(|e| e.to_string())?;

    let mut matches_created = 0;

    for edge in edges {
        let existing = matches
            .find_for_pair_group(
                edge.user1_id,
                edge.user2_id,
                edge.event_id,
                &edge.group_name,
            )
            .await
            .map_err(|e| e.to_string())?;

        match existing_match_action(existing.as_ref().map(|(_, status)| status.as_str())) {
            ExistingMatchAction::Insert => {
                matches
                    .insert_pending(
                        edge.user1_id,
                        edge.user2_id,
                        edge.event_id,
                        &edge.group_name,
                    )
                    .await
                    .map_err(|e| e.to_string())?;
                matches_created += 1;
                notify_pair(&users, edge.user1_id, edge.user2_id).await;
            }
            ExistingMatchAction::Reopen => {
                // Insert is only for None; existing is Some here.
                let Some((match_id, status)) = existing else {
                    continue;
                };
                let Some(reason) = rematch_reason_for(&status) else {
                    continue;
                };
                let reopened = matches
                    .reopen_terminal(match_id, &status, reason)
                    .await
                    .map_err(|e| e.to_string())?;
                if reopened {
                    matches_created += 1;
                    notify_pair(&users, edge.user1_id, edge.user2_id).await;
                }
            }
            ExistingMatchAction::Skip => {}
        }
    }

    Ok(matches_created)
}

async fn notify_pair(users: &UserRepository, user_a: i32, user_b: i32) {
    // Notify both users. Treat missing users as "vanished"; log load errors
    // so infra failures are observable (#266).
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
