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

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminGroup {
    pub event_id: i32,
    pub event_name: String,
    pub group_name: String,
    /// Cosmetic label; UI falls back to `group_name` when unset (#430).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    pub item_count: i64,
}

/// SELECT list for the `merchandise_groups` table.
const GROUP_COLUMNS: &str = "id, event_id, group_name, description, created_by, created_at, updated_at, photo_url, display_name";

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

    /// List every group with enough context for the moderation dashboard.
    pub async fn list_all_for_admin(&self) -> Result<Vec<AdminGroup>, AppError> {
        let rows = sqlx::query(
            r#"SELECT g.event_id, e.name AS event_name, g.group_name, g.display_name,
                      COUNT(m.id) FILTER (WHERE m.is_deleted = false) AS item_count
               FROM merchandise_groups g
               JOIN events e ON e.id = g.event_id
               LEFT JOIN merchandise m
                 ON m.event_id = g.event_id AND m.group_name = g.group_name
               GROUP BY g.event_id, e.name, g.group_name, g.display_name
               ORDER BY e.name ASC, g.group_name ASC"#,
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .iter()
            .map(|row| AdminGroup {
                event_id: row.get("event_id"),
                event_name: row.get("event_name"),
                group_name: row.get("group_name"),
                display_name: row.get("display_name"),
                item_count: row.get("item_count"),
            })
            .collect())
    }

    /// Remove a group's user-visible state as one transaction. Merchandise is
    /// soft-deleted so inventory history remains valid; matches and favorites
    /// are deleted because they are scoped to the group itself.
    pub async fn remove_for_admin(
        &self,
        event_id: i32,
        group_name: &str,
    ) -> Result<bool, AppError> {
        let mut tx = self.pool.begin().await?;
        let exists: Option<i32> = sqlx::query_scalar(
            "SELECT id FROM merchandise_groups WHERE event_id = $1 AND group_name = $2 FOR UPDATE",
        )
        .bind(event_id)
        .bind(group_name)
        .fetch_optional(&mut *tx)
        .await?;
        if exists.is_none() {
            return Ok(false);
        }

        sqlx::query(
            r#"DELETE FROM messages
               WHERE match_id IN (
                 SELECT id FROM matches WHERE event_id = $1 AND group_name = $2
               )"#,
        )
        .bind(event_id)
        .bind(group_name)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM matches WHERE event_id = $1 AND group_name = $2")
            .bind(event_id)
            .bind(group_name)
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM group_favorites WHERE event_id = $1 AND group_name = $2")
            .bind(event_id)
            .bind(group_name)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "UPDATE merchandise SET is_deleted = true, trade_enabled = false \
             WHERE event_id = $1 AND group_name = $2",
        )
        .bind(event_id)
        .bind(group_name)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM merchandise_groups WHERE event_id = $1 AND group_name = $2")
            .bind(event_id)
            .bind(group_name)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(true)
    }

    /// Upsert a group row. The first time a group name is seen for an
    /// event, the row is created with `created_by = user_id` (and optional
    /// `photo_url` on insert only). On a subsequent call for the same
    /// `(event_id, group_name)`, only `description` is updated and
    /// `created_by` / `photo_url` are preserved — photo changes must go
    /// through the RBAC-gated update path (#404).
    pub async fn create(&self, req: CreateGroupRequest) -> Result<MerchandiseGroup, AppError> {
        let group_name = req.group_name.trim().to_string();
        if group_name.is_empty() {
            return Err(AppError::bad_request("group_name is required"));
        }
        let description = req.description.clone().unwrap_or_default();
        // Empty string → NULL so we do not store blank photo_urls.
        let photo_url = req
            .photo_url
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());

        // Verify the event exists. Cheap check that prevents orphaned
        // group rows if a client mistypes the event_id.
        let event_exists: Option<i32> = sqlx::query_scalar("SELECT id FROM events WHERE id = $1")
            .bind(req.event_id)
            .fetch_optional(&self.pool)
            .await?;
        if event_exists.is_none() {
            return Err(AppError::not_found("Event not found"));
        }

        // On conflict, never touch photo_url here — that write is gated by the
        // PUT update path (creator / group.edit RBAC). Create remains an
        // unauthenticated-ish upsert for description metadata only (#404).
        let sql = format!(
            r#"INSERT INTO merchandise_groups (event_id, group_name, description, created_by, photo_url)
               VALUES ($1, $2, $3, $4, $5)
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
            .bind(photo_url)
            .fetch_one(&self.pool)
            .await?;
        Ok(group_from_row(&row))
    }

    /// Update description (and optionally photo_url / display_name) of an
    /// existing group. Returns `None` if the group row does not yet exist
    /// (caller should use `create` first). The `group_name` key is never
    /// mutated — "renaming" is done by setting `display_name` (#425).
    ///
    /// `photo_url` and `display_name` share the same partial-update semantic:
    /// when `Some`, the value is applied (empty/whitespace string clears it to
    /// NULL); when `None`, the column is left as-is. `description` is always
    /// written (empty string clears, matching `create`).
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

        // Normalize the optional fields to: None = leave as-is,
        // Some(None) = clear to NULL, Some(Some(v)) = set to trimmed v.
        let photo_url: Option<Option<String>> = req.photo_url.as_deref().map(|raw| {
            let t = raw.trim();
            if t.is_empty() {
                None
            } else {
                Some(t.to_string())
            }
        });
        let display_name: Option<Option<String>> = req.display_name.as_deref().map(|raw| {
            let t = raw.trim();
            if t.is_empty() {
                None
            } else {
                Some(t.to_string())
            }
        });

        // Build the SET clause dynamically so omitted optional fields are
        // left untouched (a partial update that only sends description does
        // not clear photo_url / display_name).
        let mut qb = sqlx::QueryBuilder::<sqlx::Postgres>::new(
            "UPDATE merchandise_groups SET description = ",
        );
        qb.push_bind(description);
        qb.push(", updated_at = NOW()");
        if let Some(photo) = photo_url {
            qb.push(", photo_url = ").push_bind(photo);
        }
        if let Some(display) = display_name {
            qb.push(", display_name = ").push_bind(display);
        }
        qb.push(" WHERE event_id = ").push_bind(req.event_id);
        qb.push(" AND group_name = ").push_bind(&group_name);
        qb.push(" RETURNING ");
        qb.push(GROUP_COLUMNS);

        let updated = qb.build().fetch_one(&self.pool).await?;
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
