use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::inventory::InventoryRepository;
use crate::services::match_lifecycle::MatchLifecycleService;
use axum::{
    Json,
    extract::{Path, State},
};
use std::sync::Arc;

/// Upsert inventory. WANT/TRADE writes re-evaluate match mutual capacity
/// (ADR 0010) via [`MatchLifecycleService::update_inventory`].
pub async fn update_inventory(
    State(lifecycle): State<Arc<MatchLifecycleService>>,
    Json(payload): Json<UpdateInventoryRequest>,
) -> Result<Json<InventoryItem>, AppError> {
    let item = lifecycle
        .update_inventory(
            payload.user_id,
            payload.merch_id,
            &payload.status,
            payload.quantity,
        )
        .await?;
    Ok(Json(item))
}

pub async fn get_user_inventory(
    State(inventory): State<Arc<InventoryRepository>>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<InventoryItem>>, AppError> {
    let items = inventory.list_for_user(user_id).await?;
    Ok(Json(items))
}
