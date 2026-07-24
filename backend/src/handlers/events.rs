//! Handlers for event-related operations.
//!
//! Thin HTTP layer: parse/validate, authz gates, map responses.
//! Multi-step create/transfer transactions live in
//! [`crate::services::event::EventService`]; single-statement SQL lives in:
//! - [`crate::repositories::event::EventRepository`]
//! - [`crate::repositories::event_favorites::EventFavoritesRepository`]
//! - [`crate::repositories::event_views::EventViewsRepository`]
//! - [`crate::repositories::group_favorites::GroupFavoritesRepository`]

use crate::error::AppError;
use crate::generated::ymatch::*;
use crate::handlers::common::{TransferCreatorRequest, UserIdQuery};
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
    // ADR 0004 §5: EventService owns the event row + `event/creator` role
    // assignment in one transaction.
    let event = state
        .event_service
        .create(&payload.name, payload.creator_id, payload.status.as_deref())
        .await?;
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

/// Resolve the caller from the `?user_id=` query param and require they hold
/// `event.member.manage` on `event_id` (ADR 0004 §5 / #442): the event
/// `creator` or `editor`, or the admin superuser bypass. There is deliberately
/// no `*.any` override for this permission, so a global moderator cannot use
/// the public members API (they use the admin path with
/// `event.member.manage.any` instead, #432).
///
/// The event's existence is confirmed (404) **before** the RBAC check, so a
/// missing event is reported as 404 rather than leaked as a 403 to a caller
/// who lacks the event role — matches `update_event`'s convention.
async fn require_event_member_manage(
    state: &AppState,
    caller_user_id: Option<i32>,
    event_id: i32,
) -> Result<(), AppError> {
    let uid =
        caller_user_id.ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(uid).await?;
    let _ = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;
    state
        .rbac_service
        .check(
            &user,
            &Scope::Event(event_id),
            Permission::EventMemberManage,
        )
        .await?;
    Ok(())
}

/// Assign the `event/editor` role to `target_id` for `event_id`
/// (`POST /api/v1/events/:id/members/:target_id`). Guarded by
/// `event.member.manage` (event creator or editor, #442) + admin bypass.
/// Idempotent.
pub async fn assign_event_member(
    State(state): State<AppState>,
    Path((event_id, target_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_event_member_manage(&state, query.user_id, event_id).await?;
    // Target must exist (404) — checked after the RBAC guard so an
    // unauthorized caller cannot probe user ids.
    state
        .users
        .get_by_id(target_id)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;
    state.rbac.assign_event_editor(target_id, event_id).await?;
    Ok(StatusCode::OK)
}

/// Revoke the `event/editor` role from `target_id` for `event_id`
/// (`DELETE /api/v1/events/:id/members/:target_id`). Guarded by
/// `event.member.manage` (event creator or editor, #442) + admin bypass.
/// Idempotent: a no-op if the user holds no editor role. The event `creator`
/// role is never removed here — the underlying SQL filters `role_id` to
/// `editor`.
pub async fn revoke_event_member(
    State(state): State<AppState>,
    Path((event_id, target_id)): Path<(i32, i32)>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<StatusCode, AppError> {
    require_event_member_manage(&state, query.user_id, event_id).await?;
    state.rbac.revoke_event_editor(target_id, event_id).await?;
    Ok(StatusCode::OK)
}

/// List the event-scoped role assignments for `event_id`
/// (`GET /api/v1/events/:id/members`). Guarded by `event.member.manage`
/// (event creator or editor, #442) + admin bypass.
pub async fn list_event_members(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<ListEventMembersResponse>, AppError> {
    require_event_member_manage(&state, query.user_id, event_id).await?;
    let members = state.rbac.list_event_members(event_id).await?;
    Ok(Json(ListEventMembersResponse { members }))
}

/// Self-service event creator transfer
/// (`PUT /api/v1/events/:id/creator`). Callable only by the **current** event
/// creator (ownership of `events.creator_id`). Editors with
/// `event.member.manage` cannot transfer. Global staff use the admin path
/// (`event.creator.transfer`, #432). Does **not** auto-promote the previous
/// creator to `editor` (same default as #432).
///
/// Ownership is re-checked under `SELECT … FOR UPDATE` inside the write
/// transaction so concurrent transfers cannot leave multiple live
/// `event/creator` role rows (#445).
pub async fn self_transfer_event_creator(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
    Json(payload): Json<TransferCreatorRequest>,
) -> Result<StatusCode, AppError> {
    let uid = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(uid).await?;

    // Fast-path 404/authz before opening a transaction so a missing event is
    // not leaked as a 403 and banned/missing targets fail without a lock.
    let previous = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;

    if previous != Some(user.id) {
        return Err(AppError::forbidden(
            "Only the event creator can transfer ownership",
        ));
    }

    if previous == Some(payload.new_creator_id) {
        return Err(AppError::bad_request("User is already the event creator"));
    }

    let target = state
        .users
        .get_by_id(payload.new_creator_id)
        .await?
        .ok_or_else(|| AppError::not_found("Target user not found"))?;
    if target.is_banned.unwrap_or(false) {
        return Err(AppError::bad_request("Target user is banned"));
    }

    // Ownership is re-checked under `SELECT … FOR UPDATE` inside the service
    // so concurrent transfers cannot leave multiple live `event/creator` rows.
    use crate::services::event::TransferCaller;
    state
        .event_service
        .transfer_creator(
            event_id,
            payload.new_creator_id,
            TransferCaller::SelfService {
                expected_creator_id: user.id,
            },
        )
        .await?;
    Ok(StatusCode::OK)
}

/// Report the caller's effective standing on `event_id`
/// (`GET /api/v1/events/:id/my-role`). Unlike [`list_event_members`], this is
/// **not** gated by `event.member.manage`: any active caller may read their
/// own role, so a plain viewer can pre-gate the Add Merch button (#366)
/// instead of discovering the 403 on click.
///
/// The response carries the caller's event-scoped membership (`role`), whether
/// a global admin/moderator role is in effect (`global_override`), the
/// **exact** `merch.create` decision the [`create_merch`](crate::handlers::merch)
/// handler enforces (`can_create_merch`), the **exact** `group.edit`
/// decision the [`update_event_group`](crate::handlers::groups) handler enforces
/// for a non-creator (`can_edit_group`), and self-service member UI gates
/// (`can_manage_editors`, `can_transfer_creator`, #442) — each computed via
/// the same [`RbacService::check`] (or ownership) so the frontend gate is not
/// a re-derivation. The group creator ownership short-circuit stays a frontend
/// check.
///
/// The event's existence is confirmed (404) before any role query, matching
/// [`update_event`]'s 404-before-decide convention.
pub async fn get_my_event_role(
    State(state): State<AppState>,
    Path(event_id): Path<i32>,
    axum::extract::Query(query): axum::extract::Query<UserIdQuery>,
) -> Result<Json<MyEventRoleResponse>, AppError> {
    let uid = query
        .user_id
        .ok_or_else(|| AppError::bad_request("user_id query parameter required"))?;
    let user = state.policy.verify_active(uid).await?;
    let previous_creator = state
        .events
        .get_creator(event_id)
        .await?
        .ok_or_else(|| AppError::not_found("Event not found"))?;

    let role = state
        .rbac
        .event_role_name(user.id, event_id)
        .await?
        .unwrap_or_else(|| "none".to_string());
    let global_override = matches!(
        state.rbac.global_role_name(user.id).await?,
        Some(ref g) if g == "admin" || g == "moderator"
    );
    let can_create_merch = state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::MerchCreate)
        .await
        .is_ok();
    let can_edit_group = state
        .rbac_service
        .check(&user, &Scope::Event(event_id), Permission::GroupEdit)
        .await
        .is_ok();
    let can_manage_editors = state
        .rbac_service
        .check(
            &user,
            &Scope::Event(event_id),
            Permission::EventMemberManage,
        )
        .await
        .is_ok();
    // Self-service transfer is ownership-based, not permission-based: only
    // the current creator_id may transfer (editors with member.manage cannot).
    let can_transfer_creator = previous_creator == Some(user.id);

    Ok(Json(MyEventRoleResponse {
        role,
        global_override,
        can_create_merch,
        can_edit_group,
        can_manage_editors,
        can_transfer_creator,
    }))
}
