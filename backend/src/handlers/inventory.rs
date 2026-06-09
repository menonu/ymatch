use crate::error::AppError;
use crate::generated::ymatch::*;
use axum::{
    Json,
    extract::{Path, State},
};
use sqlx::{PgPool, Row};

pub async fn update_inventory(
    State(pool): State<PgPool>,
    Json(payload): Json<UpdateInventoryRequest>,
) -> Result<Json<InventoryItem>, AppError> {
    let row = sqlx::query(
        r#"
        INSERT INTO inventory (user_id, merch_id, status, quantity)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id, merch_id, status)
        DO UPDATE SET quantity = EXCLUDED.quantity, updated_at = NOW()
        RETURNING id, user_id, merch_id, status, quantity
        "#,
    )
    .bind(payload.user_id)
    .bind(payload.merch_id)
    .bind(payload.status)
    .bind(payload.quantity)
    .fetch_one(&pool)
    .await?;

    Ok(Json(InventoryItem {
        id: row.get("id"),
        user_id: row.get("user_id"),
        merch_id: row.get("merch_id"),
        status: row.get("status"),
        quantity: row.get("quantity"),
        merch_name: Some("".to_string()),
        photo_url: None,
        group_name: None,
    }))
}

pub async fn get_user_inventory(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<InventoryItem>>, AppError> {
    let rows = sqlx::query(
        r#"
        SELECT
            i.id, i.user_id, i.merch_id, i.status, i.quantity,
            m.name as merch_name, m.photo_url, m.group_name
        FROM inventory i
        JOIN merchandise m ON i.merch_id = m.id
        WHERE i.user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await?;

    let items = rows
        .into_iter()
        .map(|row| InventoryItem {
            id: row.get("id"),
            user_id: row.get("user_id"),
            merch_id: row.get("merch_id"),
            status: row.get("status"),
            quantity: row.get("quantity"),
            merch_name: Some(row.get("merch_name")),
            photo_url: row.get("photo_url"),
            group_name: row.get("group_name"),
        })
        .collect();

    Ok(Json(items))
}
