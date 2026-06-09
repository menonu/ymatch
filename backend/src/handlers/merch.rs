use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::mappers::merch_from_row;
use crate::routes::AppState;
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use sqlx::{PgPool, Row};

#[derive(serde::Deserialize)]
pub struct ListMerchQuery {
    pub user_id: Option<i32>,
}

const MERCH_COLUMNS: &str = "id, event_id, name, photo_url, group_name, sort_order, status, is_deleted, trade_enabled, creator_id";

pub async fn list_all_merch(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<Merchandise>>, AppError> {
    let rows = sqlx::query(&format!(
        "SELECT {} FROM merchandise WHERE is_deleted = false ORDER BY id ASC",
        MERCH_COLUMNS
    ))
    .fetch_all(&pool)
    .await?;

    let merch = rows.iter().map(merch_from_row).collect();
    Ok(Json(merch))
}

pub async fn list_merch(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<ListMerchQuery>,
) -> Result<Json<Vec<Merchandise>>, AppError> {
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
    .await?;

    let merch = rows.iter().map(merch_from_row).collect();
    Ok(Json(merch))
}

pub async fn create_merch(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    Json(payload): Json<CreateMerchRequest>,
) -> Result<Json<Merchandise>, AppError> {
    if let Some(creator_id) = payload.creator_id {
        state.policy.verify_active(creator_id).await?;
    }

    let group = payload.group_name.as_deref().unwrap_or("").trim();
    if group.is_empty() {
        return Err(AppError::bad_request("group_name is required"));
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
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(merch_from_row(&row)))
}

pub async fn update_merch(
    State(state): State<AppState>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    Json(payload): Json<UpdateMerchRequest>,
) -> Result<Json<Merchandise>, AppError> {
    let user = state.policy.verify_active(payload.user_id).await?;

    let row = sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?;
    let creator_id: Option<i32> = row.get("creator_id");

    state
        .policy
        .require_owner_or_role(&user, creator_id.unwrap_or(-1), &["admin", "moderator"])?;

    let mut sets = Vec::new();
    let mut idx = 2; // $1=merch_id, $2=event_id
    if payload.name.is_some() {
        idx += 1;
        sets.push(format!("name = ${}", idx));
    }
    if payload.photo_url.is_some() {
        idx += 1;
        sets.push(format!("photo_url = ${}", idx));
    }
    if payload.group_name.is_some() {
        idx += 1;
        sets.push(format!("group_name = ${}", idx));
    }

    if sets.is_empty() {
        return Err(AppError::bad_request("No fields to update"));
    }

    let sql = format!(
        "UPDATE merchandise SET {} WHERE id = $1 AND event_id = $2 RETURNING {}",
        sets.join(", "),
        MERCH_COLUMNS
    );

    let mut q = sqlx::query(&sql).bind(merch_id).bind(event_id);
    if let Some(ref name) = payload.name {
        q = q.bind(name);
    }
    if let Some(ref photo_url) = payload.photo_url {
        q = q.bind(photo_url);
    }
    if let Some(ref group_name) = payload.group_name {
        q = q.bind(group_name);
    }

    let updated = q.fetch_one(&state.pool).await?;

    Ok(Json(merch_from_row(&updated)))
}

pub async fn publish_merch(
    State(state): State<AppState>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    Json(payload): Json<UserActionRequest>,
) -> Result<StatusCode, AppError> {
    let user = state.policy.verify_active(payload.user_id).await?;

    let row = sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?;
    let creator_id: Option<i32> = row.get("creator_id");

    state
        .policy
        .require_owner_or_role(&user, creator_id.unwrap_or(-1), &["admin", "moderator"])?;

    sqlx::query("UPDATE merchandise SET status = 'published' WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .execute(&state.pool)
        .await?;

    Ok(StatusCode::OK)
}

pub async fn delete_merch_by_creator(
    State(state): State<AppState>,
    Path((event_id, merch_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<ListMerchQuery>,
) -> Result<StatusCode, AppError> {
    let requester_id = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(requester_id).await?;

    let row = sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
        .bind(merch_id)
        .bind(event_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::not_found("Merchandise not found"))?;
    let creator_id: Option<i32> = row.get("creator_id");

    // Check: event creator also allowed
    let event_row = sqlx::query("SELECT creator_id FROM events WHERE id = $1")
        .bind(event_id)
        .fetch_optional(&state.pool)
        .await?;
    let event_creator_id = event_row.and_then(|r| r.get::<Option<i32>, _>("creator_id"));

    let is_merch_creator = creator_id.is_some() && creator_id == Some(user.id);
    let is_event_creator = event_creator_id.is_some() && event_creator_id == Some(user.id);
    let is_elevated = user.role == "admin" || user.role == "moderator";

    if !is_merch_creator && !is_event_creator && !is_elevated {
        return Err(AppError::forbidden("Not authorized to delete this item"));
    }

    // Soft-delete if any user has inventory referencing this merch
    let has_inventory = sqlx::query(
        "SELECT EXISTS(SELECT 1 FROM inventory WHERE merch_id = $1 AND quantity > 0) as has_inv",
    )
    .bind(merch_id)
    .fetch_one(&state.pool)
    .await?;

    let has_inv: bool = has_inventory.get("has_inv");

    if has_inv {
        sqlx::query(
            "UPDATE merchandise SET is_deleted = true, trade_enabled = false WHERE id = $1",
        )
        .bind(merch_id)
        .execute(&state.pool)
        .await?;
    } else {
        sqlx::query("DELETE FROM merchandise WHERE id = $1")
            .bind(merch_id)
            .execute(&state.pool)
            .await?;
    }

    Ok(StatusCode::OK)
}

pub async fn update_merch_sort_order(
    State(pool): State<PgPool>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UpdateMerchSortOrderRequest>,
) -> Result<StatusCode, AppError> {
    if payload.event_id != event_id {
        return Err(AppError::bad_request("Event ID mismatch"));
    }

    let mut tx = pool.begin().await?;

    for (merch_id, sort_order) in payload.sort_orders {
        sqlx::query("UPDATE merchandise SET sort_order = $1 WHERE id = $2 AND event_id = $3")
            .bind(sort_order)
            .bind(merch_id)
            .bind(event_id)
            .execute(&mut *tx)
            .await?;
    }

    tx.commit().await?;

    Ok(StatusCode::OK)
}
