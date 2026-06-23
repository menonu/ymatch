use sqlx::{PgPool, Row};

pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    // 1. Fetch all 'WANT' items, joining with merchandise to get group_name
    // Skip items from deleted/trade-disabled merchandise and banned users
    let rows = sqlx::query(
        r#"
        SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.group_name 
        FROM inventory i
        JOIN merchandise m ON i.merch_id = m.id
        JOIN users u ON i.user_id = u.id
        WHERE i.status = 'WANT' 
          AND m.is_deleted = false AND m.trade_enabled = true
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
        let want_group_name: Option<String> = want_row.get("group_name");

        // Potential partners who are TRADING what User A wants (exclude banned users)
        let potential_partners = sqlx::query(
            r#"SELECT i.user_id, i.merch_id FROM inventory i
            JOIN users u ON i.user_id = u.id
            WHERE i.merch_id = $1 AND i.status = 'TRADE' AND i.user_id != $2
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

            // Does Partner (User B) WANT anything that User A is TRADING, AND is it in the same group?
            let user_a_trades = sqlx::query(
                r#"
                SELECT i.merch_id 
                FROM inventory i
                JOIN merchandise m ON i.merch_id = m.id
                WHERE i.user_id = $1 AND i.status = 'TRADE'
                  AND (m.group_name = $2 OR ($2 IS NULL AND m.group_name IS NULL))
                "#,
            )
            .bind(want_user_id)
            .bind(&want_group_name)
            .fetch_all(pool)
            .await
            .map_err(|e| e.to_string())?;

            for a_trade_row in user_a_trades {
                let a_trade_merch_id: i32 = a_trade_row.get("merch_id");

                // Check if Partner WANTS this item
                let partner_want = sqlx::query("SELECT id FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'WANT'")
                    .bind(partner_id)
                    .bind(a_trade_merch_id)
                    .fetch_optional(pool)
                    .await
                    .map_err(|e| e.to_string())?;

                if partner_want.is_some() {
                    // MATCH FOUND!
                    // Check if match already exists to avoid duplicates
                    let existing_match = sqlx::query(
                        "SELECT id FROM matches WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)"
                    )
                    .bind(want_user_id)
                    .bind(partner_id)
                    .fetch_optional(pool)
                    .await
                    .map_err(|e| e.to_string())?;

                    if existing_match.is_none() {
                        sqlx::query(
                            "INSERT INTO matches (user1_id, user2_id, status, created_at) VALUES ($1, $2, 'PENDING', NOW())"
                        )
                        .bind(want_user_id)
                        .bind(partner_id)
                        .execute(pool)
                        .await
                        .map_err(|e| e.to_string())?;

                        matches_created += 1;

                        // Notify both users
                        let user1_row =
                            sqlx::query("SELECT username, device_token FROM users WHERE id = $1")
                                .bind(want_user_id)
                                .fetch_one(pool)
                                .await
                                .ok();
                        let user2_row =
                            sqlx::query("SELECT username, device_token FROM users WHERE id = $1")
                                .bind(partner_id)
                                .fetch_one(pool)
                                .await
                                .ok();

                        if let (Some(u1), Some(u2)) = (user1_row, user2_row) {
                            let u1_token: Option<String> = u1.get("device_token");
                            let u2_token: Option<String> = u2.get("device_token");
                            let u1_name: String = u1.get("username");
                            let u2_name: String = u2.get("username");

                            if let Some(token) = u1_token {
                                crate::notifications::send_match_notification(&token, &u2_name)
                                    .await;
                            }
                            if let Some(token) = u2_token {
                                crate::notifications::send_match_notification(&token, &u1_name)
                                    .await;
                            }
                        }
                    }
                }
            }
        }
    }

    Ok(matches_created)
}
