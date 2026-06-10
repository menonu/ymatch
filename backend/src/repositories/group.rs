//! Merchandise group repository.
//!
//! [`MerchandiseGroupRepository`] is the abstract interface for the
//! `merchandise_groups` table introduced in Issue #128. Each row represents
//! metadata (description, creator) for a group identified by
//! `(event_id, group_name)`.
//!
//! In Phase 3 of #163 this absorbs the work that was originally in PR #162.

use crate::error::AppError;
use crate::generated::ymatch::{
    CreateGroupRequest, ListGroupsResponse, MerchandiseGroup, UpdateGroupRequest,
};
use crate::handlers::mappers::group_from_row;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};

/// SELECT list for the `merchandise_groups` table.
const GROUP_COLUMNS: &str =
    "id, event_id, group_name, description, created_by, created_at, updated_at";

/// Abstract merchandise group repository.
pub trait MerchandiseGroupRepository: Send + Sync {
    /// List all groups for an event, ordered by group_name.
    fn list_for_event<'a>(
        &'a self,
        event_id: i32,
    ) -> RepositoryFuture<'a, Result<ListGroupsResponse, AppError>>;

    /// Upsert a group row. The first time a group name is seen for an
    /// event, the row is created with `created_by = user_id`. On a
    /// subsequent call for the same `(event_id, group_name)`, the
    /// description is updated and `created_by` is preserved.
    fn create<'a>(
        &'a self,
        req: CreateGroupRequest,
    ) -> RepositoryFuture<'a, Result<MerchandiseGroup, AppError>>;

    /// Update the description of an existing group. Returns `None` if the
    /// group row does not yet exist (caller should use `create` first).
    fn update<'a>(
        &'a self,
        req: UpdateGroupRequest,
    ) -> RepositoryFuture<'a, Result<Option<MerchandiseGroup>, AppError>>;

    /// Fetch a group's `created_by` (None = unowned, Some = creator user id)
    /// for the policy layer. Returns `None` if the group row does not exist.
    fn get_creator<'a>(
        &'a self,
        event_id: i32,
        group_name: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<Option<i32>>, AppError>>;

    /// Fetch the full group row, or `None` if not present.
    fn get<'a>(
        &'a self,
        event_id: i32,
        group_name: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<MerchandiseGroup>, AppError>>;
}

/// PostgreSQL implementation of [`MerchandiseGroupRepository`].
pub struct PgMerchandiseGroupRepository {
    pool: PgPool,
}

impl PgMerchandiseGroupRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl MerchandiseGroupRepository for PgMerchandiseGroupRepository {
    fn list_for_event<'a>(
        &'a self,
        event_id: i32,
    ) -> RepositoryFuture<'a, Result<ListGroupsResponse, AppError>> {
        Box::pin(async move {
            let sql = format!(
                "SELECT {} FROM merchandise_groups WHERE event_id = $1 ORDER BY group_name ASC",
                GROUP_COLUMNS
            );
            let rows = sqlx::query(&sql)
                .bind(event_id)
                .fetch_all(&self.pool)
                .await?;
            let groups: Vec<MerchandiseGroup> = rows.iter().map(group_from_row).collect();
            Ok(ListGroupsResponse { groups })
        })
    }

    fn create<'a>(
        &'a self,
        req: CreateGroupRequest,
    ) -> RepositoryFuture<'a, Result<MerchandiseGroup, AppError>> {
        let pool = self.pool.clone();
        Box::pin(async move {
            let group_name = req.group_name.trim().to_string();
            if group_name.is_empty() {
                return Err(AppError::bad_request("group_name is required"));
            }
            let description = req.description.clone().unwrap_or_default();

            // Verify the event exists. Cheap check that prevents orphaned
            // group rows if a client mistypes the event_id.
            let event_exists: Option<i32> =
                sqlx::query_scalar("SELECT id FROM events WHERE id = $1")
                    .bind(req.event_id)
                    .fetch_optional(&pool)
                    .await?;
            if event_exists.is_none() {
                return Err(AppError::not_found("Event not found"));
            }

            let sql = format!(
                r#"INSERT INTO merchandise_groups (event_id, group_name, description, created_by)
                   VALUES ($1, $2, $3, $4)
                   ON CONFLICT (event_id, group_name) DO UPDATE
                     SET description = EXCLUDED.description,
                         updated_at = NOW()
                   RETURNING {}"#,
                GROUP_COLUMNS
            );
            let row = sqlx::query(&sql)
                .bind(req.event_id)
                .bind(&group_name)
                .bind(&description)
                .bind(req.user_id)
                .fetch_one(&pool)
                .await?;
            Ok(group_from_row(&row))
        })
    }

    fn update<'a>(
        &'a self,
        req: UpdateGroupRequest,
    ) -> RepositoryFuture<'a, Result<Option<MerchandiseGroup>, AppError>> {
        let pool = self.pool.clone();
        Box::pin(async move {
            let group_name = req.group_name.trim().to_string();
            if group_name.is_empty() {
                return Err(AppError::bad_request("group_name is required"));
            }

            // Existence check using a cheap scalar.
            let exists: Option<i32> = sqlx::query_scalar(
                "SELECT id FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
            )
            .bind(req.event_id)
            .bind(&group_name)
            .fetch_optional(&pool)
            .await?;
            if exists.is_none() {
                return Ok(None);
            }

            let description = req.description.clone().unwrap_or_default();

            let updated = sqlx::query(&format!(
                r#"UPDATE merchandise_groups
                   SET description = $1, updated_at = NOW()
                   WHERE event_id = $2 AND group_name = $3
                   RETURNING {}"#,
                GROUP_COLUMNS
            ))
            .bind(&description)
            .bind(req.event_id)
            .bind(&group_name)
            .fetch_one(&pool)
            .await?;

            Ok(Some(group_from_row(&updated)))
        })
    }

    fn get_creator<'a>(
        &'a self,
        event_id: i32,
        group_name: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<Option<i32>>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(
                "SELECT created_by FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
            )
            .bind(event_id)
            .bind(group_name)
            .fetch_optional(&self.pool)
            .await?;
            Ok(row.map(|r| r.get::<Option<i32>, _>("created_by")))
        })
    }

    fn get<'a>(
        &'a self,
        event_id: i32,
        group_name: &'a str,
    ) -> RepositoryFuture<'a, Result<Option<MerchandiseGroup>, AppError>> {
        Box::pin(async move {
            let row = sqlx::query(&format!(
                "SELECT {} FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
                GROUP_COLUMNS
            ))
            .bind(event_id)
            .bind(group_name)
            .fetch_optional(&self.pool)
            .await?;
            Ok(row.as_ref().map(group_from_row))
        })
    }
}
