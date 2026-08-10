//! Web Push subscription HTTP handlers (ADR 0015 / #179 part 2).
//!
//! - Public VAPID key for `pushManager.subscribe`
//! - Register / unregister browser `PushSubscription` rows
//!
//! Matching delivery (Web Push send) is a later PR; this module only
//! persists subscriptions and exposes the public key when configured.

use crate::error::AppError;
use crate::handlers::common::{UserIdQuery, require_active_query_user};
use crate::routes::AppState;
use axum::{
    extract::{Query, State},
    response::Json,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

/// GET /api/v1/push/vapid-public-key
///
/// No auth — the VAPID application-server key is public by design.
/// Returns 404 when VAPID is not configured (local/CI default; push disabled).
pub async fn get_vapid_public_key(
    State(state): State<AppState>,
) -> Result<Json<VapidPublicKeyResponse>, AppError> {
    let public_key = state
        .vapid_public_key
        .as_deref()
        .filter(|k| !k.is_empty())
        .ok_or_else(|| AppError::not_found("VAPID not configured"))?;
    Ok(Json(VapidPublicKeyResponse {
        public_key: public_key.to_string(),
    }))
}

/// PUT /api/v1/push/subscriptions?user_id=
///
/// Upsert the caller's browser subscription. Body matches the browser
/// `PushSubscription` JSON shape (nested `keys`) with optional `userAgent`.
pub async fn upsert_push_subscription(
    State(state): State<AppState>,
    Query(query): Query<UserIdQuery>,
    Json(body): Json<UpsertPushSubscriptionRequest>,
) -> Result<Json<Value>, AppError> {
    let user = require_active_query_user(&state, query.user_id).await?;
    let endpoint = require_nonempty(body.endpoint.as_deref(), "endpoint")?;
    let p256dh = require_nonempty(body.keys.p256dh.as_deref(), "keys.p256dh")?;
    let auth = require_nonempty(body.keys.auth.as_deref(), "keys.auth")?;

    let sub = state
        .push_subscriptions
        .upsert(
            user.id,
            endpoint,
            p256dh,
            auth,
            body.user_agent.as_deref().filter(|s| !s.is_empty()),
        )
        .await?;

    Ok(Json(json!({
        "id": sub.id,
        "userId": sub.user_id,
        "endpoint": sub.endpoint,
    })))
}

/// DELETE /api/v1/push/subscriptions?user_id=
///
/// Remove the caller's subscription for the given endpoint. Idempotent:
/// missing row still returns 200 with `deleted: false`.
pub async fn delete_push_subscription(
    State(state): State<AppState>,
    Query(query): Query<UserIdQuery>,
    Json(body): Json<DeletePushSubscriptionRequest>,
) -> Result<Json<Value>, AppError> {
    let user = require_active_query_user(&state, query.user_id).await?;
    let endpoint = require_nonempty(body.endpoint.as_deref(), "endpoint")?;

    let deleted = state
        .push_subscriptions
        .delete_by_endpoint(user.id, endpoint)
        .await?;

    Ok(Json(json!({ "deleted": deleted })))
}

fn require_nonempty<'a>(value: Option<&'a str>, field: &str) -> Result<&'a str, AppError> {
    match value.map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) => Ok(s),
        None => Err(AppError::bad_request(format!("{field} is required"))),
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VapidPublicKeyResponse {
    pub public_key: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertPushSubscriptionRequest {
    pub endpoint: Option<String>,
    pub keys: PushSubscriptionKeys,
    pub user_agent: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushSubscriptionKeys {
    pub p256dh: Option<String>,
    pub auth: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeletePushSubscriptionRequest {
    pub endpoint: Option<String>,
}
