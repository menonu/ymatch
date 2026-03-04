use sqlx::{PgPool, Row};

pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    // 1. Fetch all 'WANT' items, joining with merchandise to get group_name
    let rows = sqlx::query(
        r#"
        SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.group_name 
        FROM inventory i
        JOIN merchandise m ON i.merch_id = m.id
        WHERE i.status = 'WANT' 
        ORDER BY i.updated_at ASC
        "#
    )
        .fetch_all(pool)
        .await
        .map_err(|e| e.to_string())?;

    let mut matches_created = 0;

    for want_row in rows {
        let want_user_id: i32 = want_row.get("user_id");
        let want_merch_id: i32 = want_row.get("merch_id");
        let want_group_name: Option<String> = want_row.get("group_name");

        // Potential partners who are TRADING what User A wants
        let potential_partners = sqlx::query("SELECT user_id, merch_id FROM inventory WHERE merch_id = $1 AND status = 'TRADE' AND user_id != $2")
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
                "#
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
                    }
                }
            }
        }
    }

    Ok(matches_created)
}
