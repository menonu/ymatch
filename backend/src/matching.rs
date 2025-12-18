use sqlx::PgPool;
use crate::models::{InventoryItem, Match};
use chrono::Utc;

pub async fn run_matching_algorithm(pool: &PgPool) -> Result<i32, String> {
    // 1. Fetch all 'WANT' items
    let wants = sqlx::query_as::<_, InventoryItem>(
        "SELECT * FROM inventory WHERE status = 'WANT' ORDER BY updated_at ASC"
    )
    .fetch_all(pool)
    .await
    .map_err(|e| e.to_string())?;

    let mut matches_created = 0;

    for want_item in wants {
        // User A wants Item X. Find User B who HAS Item X and WANTS something User A HAS.

        // Potential partners who HAVE what User A wants
        // In a real optimized system, this would be a single complex join query.
        // For MVP, we'll do it iteratively (N+1 query risk, but acceptable for prototype).

        let potential_partners = sqlx::query_as::<_, InventoryItem>(
            "SELECT * FROM inventory WHERE merch_id = $1 AND status = 'HAVE' AND user_id != $2"
        )
        .bind(want_item.merch_id)
        .bind(want_item.user_id)
        .fetch_all(pool)
        .await
        .map_err(|e| e.to_string())?;

        for partner_have in potential_partners {
            let partner_id = partner_have.user_id;

            // Does Partner (User B) WANT anything that User A HAS?
            // User A's HAVE list
            let user_a_haves = sqlx::query_as::<_, InventoryItem>(
                "SELECT * FROM inventory WHERE user_id = $1 AND status = 'HAVE'"
            )
            .bind(want_item.user_id)
            .fetch_all(pool)
            .await
            .map_err(|e| e.to_string())?;

            for user_a_have in user_a_haves {
                // Check if Partner WANTS this item
                let partner_want_opt = sqlx::query_as::<_, InventoryItem>(
                    "SELECT * FROM inventory WHERE user_id = $1 AND merch_id = $2 AND status = 'WANT'"
                )
                .bind(partner_id)
                .bind(user_a_have.merch_id)
                .fetch_optional(pool)
                .await
                .map_err(|e| e.to_string())?;

                if let Some(_) = partner_want_opt {
                    // MATCH FOUND!
                    // User A wants X (which B has).
                    // User B wants Y (which A has).

                    // Check if match already exists to avoid duplicates
                    let existing_match = sqlx::query!(
                        "SELECT id FROM matches WHERE (user1_id = $1 AND user2_id = $2) OR (user1_id = $2 AND user2_id = $1)",
                        want_item.user_id, partner_id
                    )
                    .fetch_optional(pool)
                    .await
                    .map_err(|e| e.to_string())?;

                    if existing_match.is_none() {
                        sqlx::query!(
                            "INSERT INTO matches (user1_id, user2_id, status, created_at) VALUES ($1, $2, 'PENDING', NOW())",
                            want_item.user_id, partner_id
                        )
                        .execute(pool)
                        .await
                        .map_err(|e| e.to_string())?;

                        matches_created += 1;
                        // Break inner loop to avoid creating multiple matches for the same pair in one run?
                        // For now, allow it, they might have multiple potential trades.
                    }
                }
            }
        }
    }

    Ok(matches_created)
}
