//! Handlers for event-related operations.
//!
//! Phase 5 of #163 splits this file into:
//! - thin handlers in this file (parse + delegate)
//! - [`crate::repositories::event::EventRepository`] (events table SQL)
//! - [`crate::repositories::event_favorites::EventFavoritesRepository`]
//! - [`crate::repositories::event_views::EventViewsRepository`]
//! - [`crate::repositories::group_favorites::GroupFavoritesRepository`]

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::repositories::event::EventRepository;
use crate::repositories::event_favorites::EventFavoritesRepository;
use crate::repositories::event_views::EventViewsRepository;
use crate::repositories::group_favorites::GroupFavoritesRepository;
use crate::routes::AppState;
use crate::services::rbac::{Permission, Scope};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use std::sync::Arc;

#[derive(serde::Deserialize)]
pub struct ListEventsQuery {
    pub user_id: Option<i32>,
}

pub async fn register_event_view(
    State(views): State<Arc<EventViewsRepository>>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UserActionRequest>,
) -> Result<StatusCode, AppError> {
    views.register_view(event_id, payload.user_id).await?;
    Ok(StatusCode::OK)
}

pub async fn list_events(
    State(events): State<Arc<EventRepository>>,
    axum::extract::Query(query): axum::extract::Query<ListEventsQuery>,
) -> Result<Json<Vec<Event>>, AppError> {
    let items = events.list_with_stats(query.user_id).await?;
    Ok(Json(items))
}

pub async fn toggle_favorite_group(
    State(groups): State<Arc<GroupFavoritesRepository>>,
    Path(event_id): Path<i32>,
    Json(payload): Json<ToggleFavoriteGroupRequest>,
) -> Result<StatusCode, AppError> {
    let is_fav = groups
        .toggle(payload.user_id, event_id, &payload.group_name)
        .await?;
    // The `is_favorite` field in the body is now advisory; the toggle
    // method is the source of truth. We don't need to return it
    // (StatusCode is enough).
    let _ = payload.is_favorite;
    let _ = is_fav;
    Ok(StatusCode::OK)
}

pub async fn list_favorite_groups(
    State(groups): State<Arc<GroupFavoritesRepository>>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<FavoriteGroup>>, AppError> {
    let items = groups.list_for_user(user_id).await?;
    Ok(Json(items))
}

pub async fn toggle_favorite(
    State(favs): State<Arc<EventFavoritesRepository>>,
    Path(event_id): Path<i32>,
    Json(payload): Json<ToggleFavoriteRequest>,
) -> Result<StatusCode, AppError> {
    let is_fav = favs.toggle(payload.user_id, event_id).await?;
    let _ = payload.is_favorite;
    let _ = is_fav;
    Ok(StatusCode::OK)
}

pub async fn create_event(
    State(state): State<AppState>,
    Json(payload): Json<CreateEventRequest>,
) -> Result<Json<Event>, AppError> {
    // ADR 0004 §4: event creation requires the global `event.create`
    // permission, granted to `moderator` and `admin` (not `user`).
    let user = state.policy.verify_active(payload.creator_id).await?;
    state
        .rbac_service
        .check(&user, &Scope::Global, Permission::EventCreate)
        .await?;
    // ADR 0004 §5: the event row and the auto-assigned `event/creator`
    // `user_roles` row are written in one transaction so the creator can
    // never end up with a persisted event they cannot edit/publish (the
    // `EventEdit` check on their own event would otherwise fail if the
    // role assignment were lost to a mid-flight failure).
    let mut tx = state.pool.begin().await?;
    let event = state
        .events
        .create(
            &mut *tx,
            &payload.name,
            payload.creator_id,
            payload.status.as_deref(),
        )
        .await?;
    state
        .rbac
        .assign_event_creator(&mut tx, payload.creator_id, event.id)
        .await?;
    tx.commit().await?;
    Ok(Json(event))
}

pub async fn update_event(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UpdateEventRequest>,
) -> Result<Json<Event>, AppError> {
    let user = state.policy.verify_active(payload.user_id).await?;
    // Confirm the event exists (404) before the RBAC check so a missing
    // event is not leaked as a 403 to a caller who lacks the event role.
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    // ADR 0004 §3: `event.edit` (event scope) is granted to the event
    // `creator` and `editor`; the admin bypass and `event.edit.any`
    // (moderator) overlap are resolved inside RbacService::check.
    state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::EventEdit)
        .await?;

    let name = payload
        .name
        .ok_or_else(|| AppError::bad_request("name is required"))?;
    let event = state
        .events
        .update_name(event_id, &name)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    Ok(Json(event))
}

pub async fn publish_event(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    Json(payload): Json<UserActionRequest>,
) -> Result<StatusCode, AppError> {
    let user = state.policy.verify_active(payload.user_id).await?;
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    // Publishing is an edit operation (ADR 0004: `event.edit` = "Edit this
    // event (rename, publish)"), gated by the same EventEdit permission.
    state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::EventEdit)
        .await?;
    state.events.publish(event_id).await?;
    Ok(StatusCode::OK)
}
