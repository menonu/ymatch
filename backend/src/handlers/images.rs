use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
};
use axum_extra::extract::Multipart;
use serde_json::{json, Value};
use std::sync::Arc;

use crate::storage::ImageStorage;

/// POST /api/v1/images/upload
/// Accepts multipart/form-data with a single "file" field.
/// Returns JSON: { "url": "https://..." }
pub async fn upload_image(
    State(storage): State<Arc<dyn ImageStorage>>,
    mut multipart: Multipart,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": format!("Multipart error: {}", e)})),
            )
        })?
    {
        let field_name = field.name().unwrap_or("").to_string();
        if field_name != "file" {
            continue;
        }

        let content_type = field
            .content_type()
            .unwrap_or("image/png")
            .to_string();

        // Validate content type
        if !content_type.starts_with("image/") {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "Only image files are allowed"})),
            ));
        }

        let original_filename = field
            .file_name()
            .unwrap_or("image.png")
            .to_string();

        let bytes = field.bytes().await.map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": format!("Failed to read file: {}", e)})),
            )
        })?;

        // Limit file size to 1MB
        if bytes.len() > 1_048_576 {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "File too large (max 1MB)"})),
            ));
        }

        // Generate unique filename
        let ext = original_filename
            .rsplit('.')
            .next()
            .unwrap_or("png");
        let unique_name = format!("{}.{}", uuid::Uuid::new_v4(), ext);

        let url = storage
            .upload(&bytes, &unique_name, &content_type)
            .await
            .map_err(|e| {
                tracing::error!("Image upload failed: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({"error": format!("Upload failed: {}", e)})),
                )
            })?;

        return Ok(Json(json!({"url": url})));
    }

    Err((
        StatusCode::BAD_REQUEST,
        Json(json!({"error": "No 'file' field found in multipart data"})),
    ))
}

/// DELETE /api/v1/images/:filename
pub async fn delete_image(
    State(storage): State<Arc<dyn ImageStorage>>,
    Path(filename): Path<String>,
) -> Result<Json<Value>, (StatusCode, Json<Value>)> {
    // Reconstruct a URL-like identifier to pass to the storage backend
    // For local: the storage will extract filename from the URL
    // For firebase: we need to reconstruct the full URL
    let url = format!("images/{}", filename);

    storage.delete(&url).await.map_err(|e| {
        tracing::error!("Image delete failed: {}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"error": format!("Delete failed: {}", e)})),
        )
    })?;

    Ok(Json(json!({"status": "deleted"})))
}
