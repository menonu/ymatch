use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::inventory::InventoryRepository;
use axum::{
    Json,
    extract::{Path, State},
};
use std::sync::Arc;

pub async fn update_inventory(
    State(inventory): State<Arc<dyn InventoryRepository>>,
    Json(payload): Json<UpdateInventoryRequest>,
) -> Result<Json<InventoryItem>, AppError> {
    let item = inventory
        .upsert(
            payload.user_id,
            payload.merch_id,
            &payload.status,
            payload.quantity,
        )
        .await?;
    Ok(Json(item))
}

pub async fn get_user_inventory(
    State(inventory): State<Arc<dyn InventoryRepository>>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<InventoryItem>>, AppError> {
    let items = inventory.list_for_user(user_id).await?;
    Ok(Json(items))
}
