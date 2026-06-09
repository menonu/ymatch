use crate::error::AppError;
use crate::storage::ImageStorage;
use axum::{
    extract::{Path, State},
    response::Json,
};
use axum_extra::extract::Multipart;
use serde_json::{Value, json};
use std::sync::Arc;

/// POST /api/v1/images/upload
/// Accepts multipart/form-data with a single "file" field.
/// Returns JSON: { "url": "https://..." }
pub async fn upload_image(
    State(storage): State<Arc<dyn ImageStorage>>,
    mut multipart: Multipart,
) -> Result<Json<Value>, AppError> {
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::bad_request(format!("Multipart error: {}", e)))?
    {
        let field_name = field.name().unwrap_or("").to_string();
        if field_name != "file" {
            continue;
        }

        let content_type = field.content_type().unwrap_or("image/png").to_string();

        // Validate content type
        if !content_type.starts_with("image/") {
            return Err(AppError::bad_request("Only image files are allowed"));
        }

        let original_filename = field.file_name().unwrap_or("image.png").to_string();

        let bytes = field
            .bytes()
            .await
            .map_err(|e| AppError::bad_request(format!("Failed to read file: {}", e)))?;

        // Limit file size to 1MB
        if bytes.len() > 1_048_576 {
            return Err(AppError::bad_request("File too large (max 1MB)"));
        }

        // Generate unique filename
        let ext = original_filename.rsplit('.').next().unwrap_or("png");
        let unique_name = format!("{}.{}", uuid::Uuid::new_v4(), ext);

        let url = storage.upload(&bytes, &unique_name, &content_type).await?;

        return Ok(Json(json!({"url": url})));
    }

    Err(AppError::bad_request(
        "No 'file' field found in multipart data",
    ))
}

/// DELETE /api/v1/images/:filename
pub async fn delete_image(
    State(storage): State<Arc<dyn ImageStorage>>,
    Path(filename): Path<String>,
) -> Result<Json<Value>, AppError> {
    // Reconstruct a URL-like identifier to pass to the storage backend
    // For local: the storage will extract filename from the URL
    // For firebase: we need to reconstruct the full URL
    let url = format!("images/{}", filename);

    storage.delete(&url).await?;

    Ok(Json(json!({"status": "deleted"})))
}
