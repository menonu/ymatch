use sqlx::{PgPool, Row};

pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    // 1. Fetch all 'WANT' items
    let rows = sqlx::query("SELECT id, user_id, merch_id, status, quantity FROM inventory WHERE status = 'WANT' ORDER BY updated_at ASC")
        .fetch_all(pool)
        .await
        .map_err(|e| e.to_string())?;

    let mut matches_created = 0;

    for want_row in rows {
        let want_user_id: i32 = want_row.get("user_id");
        let want_merch_id: i32 = want_row.get("merch_id");

        // Potential partners who HAVE what User A wants
        let potential_partners = sqlx::query("SELECT user_id, merch_id FROM inventory WHERE merch_id = $1 AND status = 'HAVE' AND user_id != $2")
            .bind(want_merch_id)
            .bind(want_user_id)
            .fetch_all(pool)
            .await
            .map_err(|e| e.to_string())?;

        for partner_row in potential_partners {
            let partner_id: i32 = partner_row.get("user_id");

            // Does Partner (User B) WANT anything that User A HAS?
            let user_a_haves = sqlx::query(
                "SELECT merch_id FROM inventory WHERE user_id = $1 AND status = 'HAVE'",
            )
            .bind(want_user_id)
            .fetch_all(pool)
            .await
            .map_err(|e| e.to_string())?;

            for a_have_row in user_a_haves {
                let a_have_merch_id: i32 = a_have_row.get("merch_id");

                // Check if Partner WANTS this item
                let partner_want = sqlx::query("SELECT id FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'WANT'")
                    .bind(partner_id)
                    .bind(a_have_merch_id)
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
