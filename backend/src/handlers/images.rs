use crate::error::AppError;
use crate::handlers::common::{UserIdQuery, require_active_query_user};
use crate::routes::AppState;
use axum::{
    extract::{Path, Query, State},
    response::Json,
};
use axum_extra::extract::Multipart;
use serde_json::{Value, json};

/// POST /api/v1/images/upload?user_id=
/// Accepts multipart/form-data with a single "file" field.
/// Returns JSON: { "url": "https://..." }
///
/// #491: requires an active caller. Full per-object ownership is not tracked
/// yet (no image owner table); active-user gate is the minimum anti-abuse bar
/// until session auth (#373) and optional ownership metadata.
pub async fn upload_image(
    State(state): State<AppState>,
    Query(query): Query<UserIdQuery>,
    mut multipart: Multipart,
) -> Result<Json<Value>, AppError> {
    require_active_query_user(&state, query.user_id).await?;

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

        let url = state
            .storage
            .upload(&bytes, &unique_name, &content_type)
            .await?;

        return Ok(Json(json!({"url": url})));
    }

    Err(AppError::bad_request(
        "No 'file' field found in multipart data",
    ))
}

/// DELETE /api/v1/images/:filename?user_id=
///
/// #491: requires an active caller. Without an ownership record any active
/// user can still delete by filename — better than fully open; tighten with
/// ownership when the storage model gains it.
pub async fn delete_image(
    State(state): State<AppState>,
    Path(filename): Path<String>,
    Query(query): Query<UserIdQuery>,
) -> Result<Json<Value>, AppError> {
    require_active_query_user(&state, query.user_id).await?;

    // Reconstruct a path-like identifier; LocalFileStorage extracts the filename.
    let url = format!("images/{}", filename);

    state.storage.delete(&url).await?;

    Ok(Json(json!({"status": "deleted"})))
}
