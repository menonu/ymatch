use crate::generated::ymatch::*;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

pub async fn list_all_matches(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<TradeMatch>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, user1_id, user2_id, status, created_at FROM matches ORDER BY created_at DESC",
    )
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut matches = Vec::new();
    for row in rows {
        let match_id: i32 = row.get("id");
        let trade_match = TradeMatch {
            id: match_id,
            user1_id: row.get("user1_id"),
            user2_id: row.get("user2_id"),
            status: row.get("status"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            other_user: None,
            user_haves: vec![],
            user_wants: vec![],
        };

        matches.push(trade_match);
    }

    Ok(Json(matches))
}

pub async fn list_matches(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<TradeMatch>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, user1_id, user2_id, status, created_at FROM matches WHERE user1_id = $1 OR user2_id = $1 ORDER BY created_at DESC"
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut matches = Vec::new();
    for row in rows {
        let match_id: i32 = row.get("id");
        let u1: i32 = row.get("user1_id");
        let u2: i32 = row.get("user2_id");
        let other_user_id = if u1 == user_id { u2 } else { u1 };

        let other_user_row = sqlx::query("SELECT id, username FROM users WHERE id = $1")
            .bind(other_user_id)
            .fetch_one(&pool)
            .await
            .ok();

        let other_user = other_user_row.map(|r| User {
            id: r.get("id"),
            username: r.get("username"),
            uuid: None,
            device_token: None,
            created_at: None,
        });

        let haves_rows = sqlx::query(
            r#"
            SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.name as merch_name, m.photo_url
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $1 AND i.status = 'TRADE' AND i.quantity > 0
            AND EXISTS (
                SELECT 1 FROM inventory w WHERE w.user_id = $2 AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0
            )
            "#
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let user_haves = haves_rows
            .into_iter()
            .map(|r| InventoryItem {
                id: r.get("id"),
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                status: r.get("status"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
                group_name: None,
            })
            .collect();

        let wants_rows = sqlx::query(
            r#"
            SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.name as merch_name, m.photo_url
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $2 AND i.status = 'TRADE' AND i.quantity > 0
            AND EXISTS (
                SELECT 1 FROM inventory w WHERE w.user_id = $1 AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0
            )
            "#
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let user_wants = wants_rows
            .into_iter()
            .map(|r| InventoryItem {
                id: r.get("id"),
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                status: r.get("status"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
                group_name: None,
            })
            .collect();

        matches.push(TradeMatch {
            id: match_id,
            user1_id: u1,
            user2_id: u2,
            status: row.get("status"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            other_user,
            user_haves,
            user_wants,
        });
    }

    Ok(Json(matches))
}

pub async fn update_match_status(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<UpdateMatchStatusRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let valid_statuses = ["ACCEPTED", "REJECTED", "COMPLETED"];
    if !valid_statuses.contains(&payload.status.as_str()) {
        return Err((StatusCode::BAD_REQUEST, "Invalid status".to_string()));
    }

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
        .bind(&payload.status)
        .bind(match_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if payload.status == "ACCEPTED" {
        let match_row = sqlx::query("SELECT user1_id, user2_id FROM matches WHERE id = $1")
            .bind(match_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

        let u1: i32 = match_row.get("user1_id");
        let u2: i32 = match_row.get("user2_id");

        sqlx::query("DELETE FROM matches WHERE status = 'PENDING' AND id != $1 AND ((user1_id = $2 AND user2_id = $3) OR (user1_id = $3 AND user2_id = $2))")
            .bind(match_id)
            .bind(u1)
            .bind(u2)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}
