use crate::repositories::match_::{REMATCH_REASON_AFTER_CANCELLED, REMATCH_REASON_AFTER_REJECTED};
use sqlx::{PgPool, Row};

// ---------------------------------------------------------------------------
// Pure matching decisions (unit-tested; used by run_matching_algorithm)
// ---------------------------------------------------------------------------

/// ADR 0001: merchandise with a NULL / empty group is not matchable.
///
/// The matcher SQL also filters `group_name IS NOT NULL`; this helper pins the
/// policy for call sites and tests without a DB.
#[inline]
pub fn is_group_matchable(group_name: Option<&str>) -> bool {
    matches!(group_name, Some(g) if !g.is_empty())
}

/// Two merchandise rows share a matchable group identity only when both have
/// the same non-null `(event_id, group_name)`.
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

pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    // 1. Fetch all 'WANT' items, joining with merchandise to get group_name
    // Skip items from deleted/trade-disabled merchandise and banned users.
    // ADR 0001: NULL-grouped merchandise is not matchable, so filter it out here
    // (no later NULL<->NULL matching branch).
    let rows = sqlx::query(
        r#"
        SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.group_name, m.event_id
        FROM inventory i
        JOIN merchandise m ON i.merch_id = m.id
        JOIN users u ON i.user_id = u.id
        WHERE i.status = 'WANT'
          -- ADR 0012 / ADR 0010: zero-qty rows do not contribute to mutual cap.
          AND i.quantity > 0
          AND m.is_deleted = false AND m.trade_enabled = true
          AND m.group_name IS NOT NULL
          AND u.is_banned = false
          AND NOT EXISTS (
            SELECT 1 FROM match_items mi
            JOIN matches mat ON mi.match_id = mat.id
            WHERE mi.merch_id = i.merch_id
              AND mat.status IN ('OFFERED', 'ACCEPTED')
              AND (mat.user1_id = i.user_id OR mat.user2_id = i.user_id)
          )
        ORDER BY i.updated_at ASC
        "#,
    )
    .fetch_all(pool)
    .await
    .map_err(|e| e.to_string())?;

    let mut matches_created = 0;

    for want_row in rows {
        let want_user_id: i32 = want_row.get("user_id");
        let want_merch_id: i32 = want_row.get("merch_id");
        // group_name is NOT NULL here (filtered above); event_id pins the group
        // identity since group_name is only unique per event.
        let want_group_name: String = want_row.get("group_name");
        let want_event_id: i32 = want_row.get("event_id");

        // Potential partners who are TRADING what User A wants (exclude banned users).
        // Merch liveness is implied by want_merch_id (outer query already filtered
        // live/trade-enabled), but re-check for defense in depth.
        let potential_partners = sqlx::query(
            r#"SELECT i.user_id, i.merch_id FROM inventory i
            JOIN users u ON i.user_id = u.id
            JOIN merchandise m ON m.id = i.merch_id
            WHERE i.merch_id = $1 AND i.status = 'TRADE' AND i.user_id != $2
              AND i.quantity > 0
              AND m.is_deleted = false AND m.trade_enabled = true
              AND u.is_banned = false
              AND NOT EXISTS (
                SELECT 1 FROM match_items mi
                JOIN matches mat ON mi.match_id = mat.id
                WHERE mi.merch_id = i.merch_id
                  AND mat.status IN ('OFFERED', 'ACCEPTED')
                  AND (mat.user1_id = i.user_id OR mat.user2_id = i.user_id)
              )"#,
        )
        .bind(want_merch_id)
        .bind(want_user_id)
        .fetch_all(pool)
        .await
        .map_err(|e| e.to_string())?;

        for partner_row in potential_partners {
            let partner_id: i32 = partner_row.get("user_id");

            // Does Partner (User B) WANT anything that User A is TRADING, AND
            // is it in the same group (same (event_id, group_name))? ADR 0001.
            // ADR 0010 / 0012: only live, trade-enabled merch contribute to cap.
            let user_a_trades = sqlx::query(
                r#"
                SELECT i.merch_id
                FROM inventory i
                JOIN merchandise m ON i.merch_id = m.id
                WHERE i.user_id = $1 AND i.status = 'TRADE' AND i.quantity > 0
                  AND m.event_id = $2 AND m.group_name = $3
                  AND m.is_deleted = false AND m.trade_enabled = true
                "#,
            )
            .bind(want_user_id)
            .bind(want_event_id)
            .bind(&want_group_name)
            .fetch_all(pool)
            .await
            .map_err(|e| e.to_string())?;

            for a_trade_row in user_a_trades {
                let a_trade_merch_id: i32 = a_trade_row.get("merch_id");

                // Partner WANT must be on live, trade-enabled merch too.
                let partner_want = sqlx::query(
                    r#"
                    SELECT i.id FROM inventory i
                    JOIN merchandise m ON m.id = i.merch_id
                    WHERE i.user_id = $1 AND i.merch_id = $2
                      AND i.status = 'WANT' AND i.quantity > 0
                      AND m.is_deleted = false AND m.trade_enabled = true
                    "#,
                )
                .bind(partner_id)
                .bind(a_trade_merch_id)
                .fetch_optional(pool)
                .await
                .map_err(|e| e.to_string())?;

                if partner_want.is_none() {
                    continue;
                }

                // MATCH FOUND!
                // Check if a match already exists for this (pair, group) to
                // avoid duplicates. ADR 0001: one match per (user1, user2,
                // group), so the same pair may have a separate match in a
                // different group — dedup only within the same group.
                //
                // ADR 0012: if the row is REJECTED or CANCELLED, reopen it
                // to PENDING (same id) instead of inserting a second row.
                // COMPLETED and active statuses are left alone.
                let existing_match = sqlx::query(
                    "SELECT id, status FROM matches
                     WHERE event_id = $3 AND group_name = $4
                       AND ((user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1))",
                )
                .bind(want_user_id)
                .bind(partner_id)
                .bind(want_event_id)
                .bind(&want_group_name)
                .fetch_optional(pool)
                .await
                .map_err(|e| e.to_string())?;

                match existing_match {
                    None => {
                        debug_assert_eq!(existing_match_action(None), ExistingMatchAction::Insert);
                        sqlx::query(
                            "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name, created_at)
                             VALUES ($1, $2, 'PENDING', $3, $4, NOW())",
                        )
                        .bind(want_user_id)
                        .bind(partner_id)
                        .bind(want_event_id)
                        .bind(&want_group_name)
                        .execute(pool)
                        .await
                        .map_err(|e| e.to_string())?;

                        matches_created += 1;
                        notify_pair(pool, want_user_id, partner_id).await;
                    }
                    Some(row) => {
                        let match_id: i32 = row.get("id");
                        let status: String = row.get("status");
                        match existing_match_action(Some(&status)) {
                            ExistingMatchAction::Reopen => {
                                if reopen_terminal_match(pool, match_id, &status).await? {
                                    matches_created += 1;
                                    notify_pair(pool, want_user_id, partner_id).await;
                                }
                            }
                            ExistingMatchAction::Skip => {}
                            ExistingMatchAction::Insert => {
                                // Row exists; Insert is only for None.
                                debug_assert!(false, "Insert action with existing row");
                            }
                        }
                    }
                }
                // One mutual edge is enough for this partner+group.
                break;
            }
        }
    }

    Ok(matches_created)
}

/// ADR 0012: reopen a REJECTED/CANCELLED match to PENDING with annotation + SYSTEM message.
///
/// Returns `true` if the row was reopened (still terminal at update time).
async fn reopen_terminal_match(
    pool: &PgPool,
    match_id: i32,
    prior_status: &str,
) -> Result<bool, String> {
    let Some(reason) = rematch_reason_for(prior_status) else {
        return Ok(false);
    };

    let mut tx = pool.begin().await.map_err(|e| e.to_string())?;

    let updated = sqlx::query(
        r#"
        UPDATE matches
        SET status = 'PENDING',
            offered_by = NULL,
            rematch_count = rematch_count + 1,
            last_terminal_status = $2,
            last_terminal_at = NOW()
        WHERE id = $1
          AND status IN ('REJECTED', 'CANCELLED')
        RETURNING id, user1_id
        "#,
    )
    .bind(match_id)
    .bind(prior_status)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;

    let Some(row) = updated else {
        tx.rollback().await.map_err(|e| e.to_string())?;
        return Ok(false);
    };

    let user1_id: i32 = row.get("user1_id");

    sqlx::query("DELETE FROM match_items WHERE match_id = $1")
        .bind(match_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;

    sqlx::query(
        r#"
        INSERT INTO messages (match_id, sender_id, content, message_type)
        VALUES ($1, $2, $3, 'SYSTEM')
        "#,
    )
    .bind(match_id)
    .bind(user1_id)
    .bind(reason)
    .execute(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;

    tx.commit().await.map_err(|e| e.to_string())?;
    Ok(true)
}

async fn notify_pair(pool: &PgPool, user_a: i32, user_b: i32) {
    // Notify both users. Treat RowNotFound as "user vanished"; log any other
    // DB error so infra failures are observable (#266).
    let load_notify_user = |user_id: i32| async move {
        match sqlx::query("SELECT username, device_token FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await
        {
            Ok(row) => Some(row),
            Err(sqlx::Error::RowNotFound) => None,
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    user_id,
                    "match notification: failed to load user"
                );
                None
            }
        }
    };
    let user1_row = load_notify_user(user_a).await;
    let user2_row = load_notify_user(user_b).await;

    if let (Some(u1), Some(u2)) = (user1_row, user2_row) {
        let u1_token: Option<String> = u1.get("device_token");
        let u2_token: Option<String> = u2.get("device_token");
        let u1_name: String = u1.get("username");
        let u2_name: String = u2.get("username");

        if let Some(token) = u1_token {
            crate::notifications::send_match_notification(&token, &u2_name).await;
        }
        if let Some(token) = u2_token {
            crate::notifications::send_match_notification(&token, &u1_name).await;
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
