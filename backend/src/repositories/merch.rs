//! Merchandise aggregate repository.
//!
//! [`MerchandiseRepository`] is the abstract interface used by handlers for
//! all `merchandise` table operations. The concrete [`PgMerchandiseRepository`]
//! implements it on top of `sqlx::PgPool`.
//!
//! Phase 3 of #163 also introduces the `merchandise_groups` first-class entity
//! (Issue #128 backend). The group description is mirrored onto each
//! `Merchandise` row via a LEFT JOIN so the frontend can render
//! `group_description` next to the group name in the existing Event Detail
//! tabs without a second round-trip.

use crate::error::AppError;
use crate::generated::ymatch::{CreateMerchRequest, Merchandise, UpdateMerchRequest};
use crate::handlers::mappers::merch_from_row;
use crate::repositories::RepositoryFuture;
use sqlx::{PgPool, Row};
use std::collections::HashMap;

/// Outcome of [`MerchandiseRepository::delete_merch`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeleteOutcome {
    /// The merch row was soft-deleted (`is_deleted = true`, `trade_enabled = false`)
    /// because inventory rows still reference it.
    SoftDeleted,
    /// The merch row was hard-deleted because no inventory references it.
    HardDeleted,
}

impl DeleteOutcome {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::SoftDeleted => "soft_deleted",
            Self::HardDeleted => "hard_deleted",
        }
    }
}

/// Abstract merchandise repository.
///
/// Mirrors the SQL queries that previously lived in `handlers/merch.rs`.
/// Group description (Issue #128) is included in the response via a
/// `LEFT JOIN merchandise_groups` so the existing frontend flow can read
/// it without a separate request.
pub trait MerchandiseRepository: Send + Sync {
    /// List all non-deleted merchandise across all events. Admin-only
    /// in practice (the caller is responsible for the role check).
    fn list_all<'a>(&'a self) -> RepositoryFuture<'a, Result<Vec<Merchandise>, AppError>>;

    /// List merchandise for one event, with creator-visible drafts included
    /// when `viewer_id` matches the merch creator.
    fn list_for_event<'a>(
        &'a self,
        event_id: i32,
        viewer_id: Option<i32>,
    ) -> RepositoryFuture<'a, Result<Vec<Merchandise>, AppError>>;

    /// Fetch a single merch row by `(event_id, merch_id)`. Returns `None` if
    /// the row does not exist or is soft-deleted.
    fn get_by_id<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<Merchandise>, AppError>>;

    /// Create a merch row. If `creator_id` is provided and a group row does
    /// not yet exist for the same `(event_id, group_name)`, it is created
    /// with empty description and `created_by = creator_id` (idempotent).
    fn create<'a>(
        &'a self,
        event_id: i32,
        req: CreateMerchRequest,
    ) -> RepositoryFuture<'a, Result<Merchandise, AppError>>;

    /// Patch-update a merch row. Only fields present in `req` are updated.
    /// Returns `None` if the row does not exist.
    fn update<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
        req: UpdateMerchRequest,
    ) -> RepositoryFuture<'a, Result<Option<Merchandise>, AppError>>;

    /// Flip a draft merch row to published.
    fn publish<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>>;

    /// Soft- or hard-delete based on whether any inventory row references
    /// this merch. The branch logic (the only place a `SELECT EXISTS(...)`
    /// from `inventory` lives) is now in one method on this trait, not
    /// duplicated between `merch::delete_merch_by_creator` and
    /// `admin::delete_merch` as in the Phase 1/2 code.
    fn delete_merch<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<DeleteOutcome>, AppError>>;

    /// Fetch the `creator_id` of a merch row, or `None` if the row does
    /// not exist. Used by `MerchPermissionPolicy` for ownership checks.
    fn get_creator<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<Option<i32>>, AppError>>;

    /// Update the `sort_order` of multiple merch rows in a single
    /// transaction. Used by `merch::update_merch_sort_order`.
    fn update_sort_orders<'a>(
        &'a self,
        event_id: i32,
        orders: HashMap<i32, i32>,
    ) -> RepositoryFuture<'a, Result<(), AppError>>;
}

/// SELECT list for the merch columns in isolation. Use this for INSERT/UPDATE
/// RETURNING paths that don't join to merchandise_groups.
const MERCH_COLUMNS: &str = "id, event_id, name, photo_url, group_name, sort_order, status, is_deleted, trade_enabled, creator_id";

/// SELECT list joined to `merchandise_groups` so each row carries the
/// `group_description` (Issue #128).
const MERCH_SELECT: &str = "m.id, m.event_id, m.name, m.photo_url, m.group_name, m.sort_order, m.status, m.is_deleted, m.trade_enabled, m.creator_id, COALESCE(g.description, '') AS group_description";

/// PostgreSQL implementation of [`MerchandiseRepository`].
pub struct PgMerchandiseRepository {
    pool: PgPool,
}

impl PgMerchandiseRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

impl MerchandiseRepository for PgMerchandiseRepository {
    fn list_all<'a>(&'a self) -> RepositoryFuture<'a, Result<Vec<Merchandise>, AppError>> {
        Box::pin(async move {
            let sql = format!(
                "SELECT {} FROM merchandise m LEFT JOIN merchandise_groups g ON g.event_id = m.event_id AND g.group_name = m.group_name WHERE m.is_deleted = false ORDER BY m.id ASC",
                MERCH_SELECT
            );
            let rows = sqlx::query(&sql).fetch_all(&self.pool).await?;
            Ok(rows.iter().map(merch_from_row).collect())
        })
    }

    fn list_for_event<'a>(
        &'a self,
        event_id: i32,
        viewer_id: Option<i32>,
    ) -> RepositoryFuture<'a, Result<Vec<Merchandise>, AppError>> {
        Box::pin(async move {
            let sql = format!(
                r#"SELECT {} FROM merchandise m
                LEFT JOIN merchandise_groups g ON g.event_id = m.event_id AND g.group_name = m.group_name
                WHERE m.event_id = $1 AND m.is_deleted = false
                AND (m.status = 'published' OR m.creator_id = $2)
                ORDER BY m.sort_order ASC, m.id ASC"#,
                MERCH_SELECT
            );
            let rows = sqlx::query(&sql)
                .bind(event_id)
                .bind(viewer_id)
                .fetch_all(&self.pool)
                .await?;
            Ok(rows.iter().map(merch_from_row).collect())
        })
    }

    fn get_by_id<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<Merchandise>, AppError>> {
        Box::pin(async move {
            let sql = format!(
                "SELECT {} FROM merchandise m LEFT JOIN merchandise_groups g ON g.event_id = m.event_id AND g.group_name = m.group_name WHERE m.id = $1 AND m.event_id = $2 AND m.is_deleted = false",
                MERCH_SELECT
            );
            let row = sqlx::query(&sql)
                .bind(merch_id)
                .bind(event_id)
                .fetch_optional(&self.pool)
                .await?;
            Ok(row.as_ref().map(merch_from_row))
        })
    }

    fn create<'a>(
        &'a self,
        event_id: i32,
        req: CreateMerchRequest,
    ) -> RepositoryFuture<'a, Result<Merchandise, AppError>> {
        let pool = self.pool.clone();
        Box::pin(async move {
            let group_name = req
                .group_name
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .ok_or_else(|| AppError::bad_request("group_name is required"))?;
            let status = req.status.as_deref().unwrap_or("published");

            // Auto-upsert: if a group row does not yet exist for
            // (event_id, group_name), create it with empty description and
            // created_by = creator_id. If it exists, do nothing (the
            // description set via NewGroupDialog is preserved).
            if let Some(creator_id) = req.creator_id {
                sqlx::query(
                    r#"INSERT INTO merchandise_groups (event_id, group_name, description, created_by)
                       VALUES ($1, $2, '', $3)
                       ON CONFLICT (event_id, group_name) DO NOTHING"#,
                )
                .bind(event_id)
                .bind(group_name)
                .bind(creator_id)
                .execute(&pool)
                .await?;
            }

            let sql = format!(
                r#"INSERT INTO merchandise (event_id, name, photo_url, group_name, creator_id, status)
                   VALUES ($1, $2, $3, $4, $5, $6)
                   RETURNING {}, '' AS group_description"#,
                MERCH_COLUMNS
            );
            let row = sqlx::query(&sql)
                .bind(event_id)
                .bind(&req.name)
                .bind(&req.photo_url)
                .bind(&req.group_name)
                .bind(req.creator_id)
                .bind(status)
                .fetch_one(&pool)
                .await?;

            // Fetch the description separately so we can return it in the
            // same response shape that the LEFT JOIN would produce.
            let description: Option<String> = sqlx::query_scalar(
                "SELECT description FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
            )
            .bind(event_id)
            .bind(group_name)
            .fetch_optional(&pool)
            .await?
            .flatten();

            let mut merch = merch_from_row(&row);
            merch.group_description = description.filter(|s| !s.is_empty());
            Ok(merch)
        })
    }

    fn update<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
        req: UpdateMerchRequest,
    ) -> RepositoryFuture<'a, Result<Option<Merchandise>, AppError>> {
        Box::pin(async move {
            let mut sets = Vec::new();
            let mut idx = 2; // $1 = merch_id, $2 = event_id
            if req.name.is_some() {
                idx += 1;
                sets.push(format!("name = ${}", idx));
            }
            if req.photo_url.is_some() {
                idx += 1;
                sets.push(format!("photo_url = ${}", idx));
            }
            if req.group_name.is_some() {
                idx += 1;
                sets.push(format!("group_name = ${}", idx));
            }

            if sets.is_empty() {
                return Err(AppError::bad_request("No fields to update"));
            }

            let sql = format!(
                "UPDATE merchandise SET {} WHERE id = $1 AND event_id = $2 RETURNING {}, '' AS group_description",
                sets.join(", "),
                MERCH_COLUMNS
            );

            let mut q = sqlx::query(&sql).bind(merch_id).bind(event_id);
            if let Some(ref name) = req.name {
                q = q.bind(name);
            }
            if let Some(ref photo_url) = req.photo_url {
                q = q.bind(photo_url);
            }
            if let Some(ref group_name) = req.group_name {
                q = q.bind(group_name);
            }

            let row = q.fetch_optional(&self.pool).await?;
            let Some(row) = row else {
                return Ok(None);
            };

            // If group_name was changed, fetch the description for the
            // new group. Otherwise fetch for the existing one.
            let new_group: Option<String> = req
                .group_name
                .clone()
                .or_else(|| row.get::<Option<String>, _>("group_name"));
            let description: Option<String> = if let Some(g) = new_group.as_deref() {
                sqlx::query_scalar(
                    "SELECT description FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
                )
                .bind(event_id)
                .bind(g)
                .fetch_optional(&self.pool)
                .await?
                .flatten()
            } else {
                None
            };

            let mut merch = merch_from_row(&row);
            merch.group_description = description.filter(|s| !s.is_empty());
            Ok(Some(merch))
        })
    }

    fn publish<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<()>, AppError>> {
        Box::pin(async move {
            let affected = sqlx::query(
                "UPDATE merchandise SET status = 'published' WHERE id = $1 AND event_id = $2",
            )
            .bind(merch_id)
            .bind(event_id)
            .execute(&self.pool)
            .await?
            .rows_affected();
            if affected == 0 {
                Ok(None)
            } else {
                Ok(Some(()))
            }
        })
    }

    fn delete_merch<'a>(
        &'a self,
        _event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<DeleteOutcome>, AppError>> {
        Box::pin(async move {
            let has_inventory: bool = sqlx::query(
                "SELECT EXISTS(SELECT 1 FROM inventory WHERE merch_id = $1 AND quantity > 0) as has_inv",
            )
            .bind(merch_id)
            .fetch_one(&self.pool)
            .await?
            .get("has_inv");

            if has_inventory {
                let affected = sqlx::query(
                    "UPDATE merchandise SET is_deleted = true, trade_enabled = false WHERE id = $1",
                )
                .bind(merch_id)
                .execute(&self.pool)
                .await?
                .rows_affected();
                Ok(if affected == 0 {
                    None
                } else {
                    Some(DeleteOutcome::SoftDeleted)
                })
            } else {
                let affected = sqlx::query("DELETE FROM merchandise WHERE id = $1")
                    .bind(merch_id)
                    .execute(&self.pool)
                    .await?
                    .rows_affected();
                Ok(if affected == 0 {
                    None
                } else {
                    Some(DeleteOutcome::HardDeleted)
                })
            }
        })
    }

    fn get_creator<'a>(
        &'a self,
        event_id: i32,
        merch_id: i32,
    ) -> RepositoryFuture<'a, Result<Option<Option<i32>>, AppError>> {
        Box::pin(async move {
            let row =
                sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
                    .bind(merch_id)
                    .bind(event_id)
                    .fetch_optional(&self.pool)
                    .await?;
            Ok(row.map(|r| r.get::<Option<i32>, _>("creator_id")))
        })
    }

    fn update_sort_orders<'a>(
        &'a self,
        event_id: i32,
        orders: HashMap<i32, i32>,
    ) -> RepositoryFuture<'a, Result<(), AppError>> {
        Box::pin(async move {
            let mut tx = self.pool.begin().await?;
            for (merch_id, sort_order) in orders {
                sqlx::query(
                    "UPDATE merchandise SET sort_order = $1 WHERE id = $2 AND event_id = $3",
                )
                .bind(sort_order)
                .bind(merch_id)
                .bind(event_id)
                .execute(&mut *tx)
                .await?;
            }
            tx.commit().await?;
            Ok(())
        })
    }
}
