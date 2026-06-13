//! Merchandise group repository.
//!
//! [`MerchandiseGroupRepository`] owns the `merchandise_groups` table
//! operations introduced in Issue #128. Each row represents metadata
//! (description, creator) for a group identified by `(event_id, group_name)`.
//!
//! Phase B-5 of #191: migrated from the previous
//! `trait MerchandiseGroupRepository + PgMerchandiseGroupRepository`
//! two-type pattern to a single concrete struct, matching the Phase A
//! shape.

use crate::error::AppError;
use crate::generated::ymatch::{
    CreateGroupRequest, ListGroupsResponse, MerchandiseGroup, UpdateGroupRequest,
};
use crate::handlers::mappers::group_from_row;
use sqlx::{PgPool, Row};

/// SELECT list for the `merchandise_groups` table.
const GROUP_COLUMNS: &str =
    "id, event_id, group_name, description, created_by, created_at, updated_at";

pub struct MerchandiseGroupRepository {
    pool: PgPool,
}

impl MerchandiseGroupRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// List all groups for an event, ordered by group_name.
    pub async fn list_for_event(&self, event_id: i32) -> Result<ListGroupsResponse, AppError> {
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
    }

    /// Upsert a group row. The first time a group name is seen for an
    /// event, the row is created with `created_by = user_id`. On a
    /// subsequent call for the same `(event_id, group_name)`, the
    /// description is updated and `created_by` is preserved.
    pub async fn create(&self, req: CreateGroupRequest) -> Result<MerchandiseGroup, AppError> {
        let group_name = req.group_name.trim().to_string();
        if group_name.is_empty() {
            return Err(AppError::bad_request("group_name is required"));
        }
        let description = req.description.clone().unwrap_or_default();

        // Verify the event exists. Cheap check that prevents orphaned
        // group rows if a client mistypes the event_id.
        let event_exists: Option<i32> = sqlx::query_scalar("SELECT id FROM events WHERE id = $1")
            .bind(req.event_id)
            .fetch_optional(&self.pool)
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
            .fetch_one(&self.pool)
            .await?;
        Ok(group_from_row(&row))
    }

    /// Update the description of an existing group. Returns `None` if the
    /// group row does not yet exist (caller should use `create` first).
    pub async fn update(
        &self,
        req: UpdateGroupRequest,
    ) -> Result<Option<MerchandiseGroup>, AppError> {
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
        .fetch_optional(&self.pool)
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
        .fetch_one(&self.pool)
        .await?;

        Ok(Some(group_from_row(&updated)))
    }

    /// Fetch a group's `created_by` (None = unowned, Some = creator user id)
    /// for the policy layer. Returns `None` if the group row does not exist.
    pub async fn get_creator(
        &self,
        event_id: i32,
        group_name: &str,
    ) -> Result<Option<Option<i32>>, AppError> {
        let row = sqlx::query(
            "SELECT created_by FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
        )
        .bind(event_id)
        .bind(group_name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| r.get::<Option<i32>, _>("created_by")))
    }

    /// Fetch the full group row, or `None` if not present.
    pub async fn get(
        &self,
        event_id: i32,
        group_name: &str,
    ) -> Result<Option<MerchandiseGroup>, AppError> {
        let row = sqlx::query(&format!(
            "SELECT {} FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
            GROUP_COLUMNS
        ))
        .bind(event_id)
        .bind(group_name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.as_ref().map(group_from_row))
    }
}
