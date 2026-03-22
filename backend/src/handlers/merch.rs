use crate::generated::ymatch::*;
use crate::handlers::permissions;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

#[derive(serde::Deserialize)]
pub struct ListMerchQuery {
    pub user_id: Option<i32>,
}

fn merch_from_row(row: &sqlx::postgres::PgRow) -> Merchandise {
    Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
        group_name: row.get("group_name"),
        sort_order: row.get::<Option<i32>, _>("sort_order"),
        status: Some(row.get("status")),
        is_deleted: Some(row.get("is_deleted")),
        trade_enabled: Some(row.get("trade_enabled")),
        creator_id: row.get("creator_id"),
    }
}

const MERCH_COLUMNS: &str =
    "id, event_id, name, photo_url, group_name, sort_order, status, is_deleted, trade_enabled, creator_id";

pub async fn list_all_merch(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    let rows = sqlx::query(&format!(
        "SELECT {} FROM merchandise WHERE is_deleted = false ORDER BY id ASC",
        MERCH_COLUMNS
    ))
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows.iter().map(merch_from_row).collect();
    Ok(Json(merch))
}

pub async fn list_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<ListMerchQuery>,
) -> Result<Json<Vec<Merchandise>>, (StatusCode, String)> {
    // Show published non-deleted items + user's own drafts
    let rows = sqlx::query(&format!(
        r#"SELECT {} FROM merchandise 
        WHERE event_id = $1 AND is_deleted = false 
        AND (status = 'published' OR creator_id = $2)
        ORDER BY sort_order ASC, id ASC"#,
        MERCH_COLUMNS
    ))
    .bind(event_id)
    .bind(query.user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let merch = rows.iter().map(merch_from_row).collect();
    Ok(Json(merch))
}

pub async fn create_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, (StatusCode, String)> {
    if let Some(creator_id) = payload.creator_id {
        let user = permissions::get_verified_user(&pool, creator_id).await?;
        permissions::require_not_banned(&user)?;
    }

    let status = payload.status.as_deref().unwrap_or("published");

    let row = sqlx::query(&format!(
        "INSERT INTO merchandise (event_id, name, photo_url, group_name, creator_id, status) VALUES ($1, $2, $3, $4, $5, $6) RETURNING {}",
        MERCH_COLUMNS
    ))
    .bind(event_id)
    .bind(&payload.name)
    .bind(&payload.photo_url)
    .bind(&payload.group_name)
    .bind(payload.creator_id)
    .bind(status)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(merch_from_row(&row)))
}

pub async fn publish_merch(
    State(pool): State<PgPool>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    Json(payload): Json<UserActionRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let user = permissions::get_verified_user(&pool, payload.user_id).await?;
    permissions::require_not_banned(&user)?;

    let row = sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((StatusCode::NOT_FOUND, "Merchandise not found".to_string()))?;
    let creator_id: Option<i32> = row.get("creator_id");

    permissions::check_ownership_or_role(&user, creator_id.unwrap_or(-1), &["admin", "moderator"])?;

    sqlx::query("UPDATE merchandise SET status = 'published' WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

pub async fn delete_merch_by_creator(
    State(pool): State<PgPool>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<ListMerchQuery>,
) -> Result<StatusCode, (StatusCode, String)> {
    let requester_id = query.user_id.ok_or((
        StatusCode::BAD_REQUEST,
        "user_id query parameter required".to_string(),
    ))?;
    let user = permissions::get_verified_user(&pool, requester_id).await?;
    permissions::require_not_banned(&user)?;

    let row = sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let row = row.ok_or((StatusCode::NOT_FOUND, "Merchandise not found".to_string()))?;
    let creator_id: Option<i32> = row.get("creator_id");

    // Check: event creator also allowed
    let event_row = sqlx::query("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    let event_creator_id = event_row.and_then(|r| r.get::<Option<i32>, _>("creator_id"));

    let is_merch_creator = creator_id.is_some() && creator_id == Some(user.id);
    let is_event_creator = event_creator_id.is_some() && event_creator_id == Some(user.id);
    let is_elevated = user.role == "admin" || user.role == "moderator";

    if !is_merch_creator && !is_event_creator && !is_elevated {
        return Err((
            StatusCode::FORBIDDEN,
            "Not authorized to delete this item".to_string(),
        ));
    }

    // Soft-delete if any user has inventory referencing this merch
    let has_inventory = sqlx::query(
        "SELECT EXISTS(SELECT 1 FROM inventory WHERE merch_id = $1 AND quantity > 0) as has_inv",
    )
    .bind(merch_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let has_inv: bool = has_inventory.get("has_inv");

    if has_inv {
        sqlx::query(
            "UPDATE merchandise SET is_deleted = true, trade_enabled = false WHERE id = $1",
        )
        .bind(merch_id)
        .execute(&pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    } else {
        sqlx::query("DELETE FROM merchandise WHERE id = $1")
            .bind(merch_id)
            .execute(&pool)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    Ok(StatusCode::OK)
}

pub async fn update_merch_sort_order(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UpdateMerchSortOrderRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    if payload.event_id != event_id {
        return Err((StatusCode::BAD_REQUEST, "Event ID mismatch".to_string()));
    }

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    for (merch_id, sort_order) in payload.sort_orders {
        sqlx::query("UPDATE merchandise SET sort_order = $1 WHERE id = $2 AND event_id = $3")
            .bind(sort_order)
            .bind(merch_id)
            .bind(event_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}
