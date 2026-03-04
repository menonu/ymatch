use sqlx::{PgPool, Row};
use crate::generated::ymatch::InventoryItem;

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
            let user_a_haves = sqlx::query("SELECT merch_id FROM inventory WHERE user_id = $1 AND status = 'HAVE'")
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

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::PgPool;

    #[sqlx::test]
    async fn test_run_matching_algorithm(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
        // 1. Setup users
        sqlx::query("INSERT INTO users (id, username, password_hash, created_at) VALUES (1, 'user1', 'hash', NOW()), (2, 'user2', 'hash', NOW())")
            .execute(&pool)
            .await?;

        // 2. Setup events and merch
        sqlx::query("INSERT INTO events (id, name, creator_id, created_at) VALUES (1, 'Test Event', 1, NOW())")
            .execute(&pool)
            .await?;
        sqlx::query("INSERT INTO merchandise (id, event_id, name, group_name) VALUES (1, 1, 'Merch 1', 'Group 1'), (2, 1, 'Merch 2', 'Group 1')")
            .execute(&pool)
            .await?;

        // 3. Setup inventory
        // User 1 WANTS Merch 1, HAS Merch 2
        // User 2 HAS Merch 1, WANTS Merch 2
        sqlx::query("INSERT INTO inventory (user_id, merch_id, status, quantity, updated_at) VALUES
            (1, 1, 'WANT', 1, NOW()),
            (1, 2, 'HAVE', 1, NOW()),
            (2, 1, 'HAVE', 1, NOW()),
            (2, 2, 'WANT', 1, NOW())")
            .execute(&pool)
            .await?;

        // 4. Run matching
        let matches_created = run_matching_algorithm(&pool).await?;

        // 5. Assert
        assert_eq!(matches_created, 1);

        // Verify match exists in db
        let match_row = sqlx::query("SELECT user1_id, user2_id, status FROM matches")
            .fetch_one(&pool)
            .await?;

        let u1: i32 = match_row.get("user1_id");
        let u2: i32 = match_row.get("user2_id");
        assert!((u1 == 1 && u2 == 2) || (u1 == 2 && u2 == 1));

        Ok(())
    }
}
