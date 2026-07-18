//! Merchandise aggregate repository.
//!
//! [`MerchandiseRepository`] owns all `merchandise` table operations. The
//! struct holds a `PgPool` and exposes plain `async fn` methods (no
//! boxed-future return, no trait) so it can be stored in
//! `Arc<MerchandiseRepository>` in `AppState` and called from handlers
//! and services alike.
//!
//! Phase A of #191: migrated from the previous `trait MerchandiseRepository +
//! PgMerchandiseRepository` two-type pattern to a single concrete struct.
//! The struct retains the same public method signatures (modulo the
//! `BoxFuture` return type), so callers and tests are unaffected.
//!
//! Phase 3 of #163 also introduces the `merchandise_groups` first-class entity
//! (Issue #128 backend). The group description is mirrored onto each
//! `Merchandise` row via a LEFT JOIN so the frontend can render
//! `group_description` next to the group name in the existing Event Detail
//! tabs without a second round-trip.

use crate::error::AppError;
use crate::generated::ymatch::{CreateMerchRequest, Merchandise, UpdateMerchRequest};
use crate::handlers::mappers::merch_from_row;
use crate::repositories::match_::{CANCEL_REASON_MERCH_DELETED, MatchRepository};
use sqlx::{PgPool, Row};

/// Whether a `sqlx::Error` is a Postgres unique-violation (SQLSTATE 23505).
fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(e, sqlx::Error::Database(db) if db.code().as_deref() == Some("23505"))
}

/// Map an INSERT/UPDATE error to a `400` when it is a duplicate-name
/// unique-violation from `uq_merchandise_live_name_per_group`; any other
/// database error falls through to the blanket `From<sqlx::Error>` impl
/// (500). Used as a race-condition backstop behind the application-level
/// pre-check in [`MerchandiseRepository::create`] / [`update`].
fn map_name_conflict(e: sqlx::Error, name: &str, group: &str) -> AppError {
    if is_unique_violation(&e) {
        AppError::bad_request(format!(
            "a merch item named '{name}' already exists in group '{group}'"
        ))
    } else {
        AppError::from(e)
    }
}

/// Outcome of [`MerchandiseRepository::delete_merch`] / [`delete_by_id`].
///
/// ADR 0008: deletion is always soft-delete; the hard-delete branch is gone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeleteOutcome {
    /// The merch row was soft-deleted (`is_deleted = true`, `trade_enabled = false`).
    /// Active matches referencing the item were moved to `CANCELLED` in the
    /// same transaction.
    SoftDeleted,
}

impl DeleteOutcome {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::SoftDeleted => "soft_deleted",
        }
    }
}

/// Concrete PostgreSQL-backed repository for the `merchandise` table.
///
/// All methods are plain `async fn` and return `Result<T, AppError>` directly
/// (no boxed-future return). The struct is `Send + Sync` via
/// the inner `PgPool` so it can be wrapped in `Arc` and shared across
/// handlers and services.
pub struct MerchandiseRepository {
    pool: PgPool,
}

impl MerchandiseRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// List all non-deleted merchandise across all events. Admin-only
    /// in practice (the caller is responsible for the role check).
    pub async fn list_all(&self) -> Result<Vec<Merchandise>, AppError> {
        let sql = format!(
            "SELECT {} FROM merchandise m LEFT JOIN merchandise_groups g ON g.event_id = m.event_id AND g.group_name = m.group_name WHERE m.is_deleted = false ORDER BY m.id ASC",
            MERCH_SELECT
        );
        let rows = sqlx::query(&sql).fetch_all(&self.pool).await?;
        Ok(rows.iter().map(merch_from_row).collect())
    }

    /// List merchandise for one event, with creator-visible drafts included
    /// when `viewer_id` matches the merch creator.
    ///
    /// ADR 0011: catalog lists are live-only (`is_deleted = false`) for every
    /// viewer — including the merch creator, moderators, and HAVE holders.
    /// Soft-deleted rows remain in the DB (ADR 0008) and still surface on
    /// holder inventory via `InventoryRepository::list_for_user`. Search is
    /// also live-only (handlers/search.rs).
    pub async fn list_for_event(
        &self,
        event_id: i32,
        viewer_id: Option<i32>,
    ) -> Result<Vec<Merchandise>, AppError> {
        let sql = format!(
            r#"SELECT {} FROM merchandise m
            LEFT JOIN merchandise_groups g ON g.event_id = m.event_id AND g.group_name = m.group_name
            WHERE m.event_id = $1
            AND m.is_deleted = false
            AND (m.status = 'published' OR m.creator_id = $2)
            ORDER BY m.id ASC"#,
            MERCH_SELECT
        );
        let rows = sqlx::query(&sql)
            .bind(event_id)
            .bind(viewer_id)
            .fetch_all(&self.pool)
            .await?;
        Ok(rows.iter().map(merch_from_row).collect())
    }

    /// Fetch a single merch row by `(event_id, merch_id)`. Returns `None` if
    /// the row does not exist or is soft-deleted.
    pub async fn get_by_id(
        &self,
        event_id: i32,
        merch_id: i32,
    ) -> Result<Option<Merchandise>, AppError> {
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
    }

    /// Create a merch row. If `creator_id` is provided and a group row does
    /// not yet exist for the same `(event_id, group_name)`, it is created
    /// with empty description and `created_by = creator_id` (idempotent).
    pub async fn create(
        &self,
        event_id: i32,
        req: CreateMerchRequest,
    ) -> Result<Merchandise, AppError> {
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
            .execute(&self.pool)
            .await?;
        }

        // Issue #299: reject a duplicate name within the same (event_id,
        // group_name) among live rows. The partial unique index
        // uq_merchandise_live_name_per_group is the race-condition backstop
        // (mapped via map_name_conflict on the INSERT below); this pre-check
        // gives a clean, specific 400 in the common case.
        let name_taken: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM merchandise \
             WHERE event_id = $1 AND group_name = $2 AND name = $3 AND is_deleted = false)",
        )
        .bind(event_id)
        .bind(group_name)
        .bind(&req.name)
        .fetch_one(&self.pool)
        .await?;
        if name_taken {
            return Err(AppError::bad_request(format!(
                "a merch item named '{}' already exists in group '{}'",
                req.name, group_name
            )));
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
            .fetch_one(&self.pool)
            .await
            .map_err(|e| map_name_conflict(e, &req.name, group_name))?;

        // Fetch the description separately so we can return it in the
        // same response shape that the LEFT JOIN would produce.
        let description: Option<String> = sqlx::query_scalar(
            "SELECT description FROM merchandise_groups WHERE event_id = $1 AND group_name = $2",
        )
        .bind(event_id)
        .bind(group_name)
        .fetch_optional(&self.pool)
        .await?
        .flatten();

        let mut merch = merch_from_row(&row);
        merch.group_description = description.filter(|s| !s.is_empty());
        Ok(merch)
    }

    /// Patch-update a merch row. Only fields present in `req` are updated.
    /// Returns `None` if the row does not exist.
    pub async fn update(
        &self,
        event_id: i32,
        merch_id: i32,
        req: UpdateMerchRequest,
    ) -> Result<Option<Merchandise>, AppError> {
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

        // Issue #299: a rename and/or group move must not collide with another
        // live row in the target (event_id, group_name, name). Resolve the
        // effective name/group (new value if patched, else the row's current
        // value) and pre-check against every other live row. The partial
        // unique index is the race backstop (mapped via map_name_conflict on
        // the UPDATE below).
        let mut conflict_name: Option<String> = None;
        let mut conflict_group: Option<String> = None;
        if req.name.is_some() || req.group_name.is_some() {
            let existing: Option<(String, Option<String>)> = sqlx::query_as(
                "SELECT name, group_name FROM merchandise \
                 WHERE id = $1 AND event_id = $2 AND is_deleted = false",
            )
            .bind(merch_id)
            .bind(event_id)
            .fetch_optional(&self.pool)
            .await?;
            if let Some((cur_name, cur_group)) = existing {
                let effective_name = req.name.clone().unwrap_or(cur_name);
                let effective_group = req.group_name.clone().or(cur_group);
                if let Some(ref g) = effective_group {
                    let name_taken: bool = sqlx::query_scalar(
                        "SELECT EXISTS(SELECT 1 FROM merchandise \
                         WHERE event_id = $1 AND group_name = $2 AND name = $3 \
                         AND id <> $4 AND is_deleted = false)",
                    )
                    .bind(event_id)
                    .bind(g)
                    .bind(&effective_name)
                    .bind(merch_id)
                    .fetch_one(&self.pool)
                    .await?;
                    if name_taken {
                        return Err(AppError::bad_request(format!(
                            "a merch item named '{effective_name}' already exists in group '{g}'"
                        )));
                    }
                }
                conflict_name = Some(effective_name);
                conflict_group = effective_group;
            }
        }

        // ADR 0008: soft-deleted rows are immutable via the update API.
        let sql = format!(
            "UPDATE merchandise SET {} WHERE id = $1 AND event_id = $2 AND is_deleted = false \
             RETURNING {}, '' AS group_description",
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

        let row = q.fetch_optional(&self.pool).await.map_err(|e| {
            // Race backstop for #299: a concurrent insert/rename hit the
            // partial unique index between our pre-check and this UPDATE.
            match (&conflict_name, &conflict_group) {
                (Some(n), Some(g)) => map_name_conflict(e, n, g),
                _ => AppError::from(e),
            }
        })?;
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
    }

    /// Flip a draft merch row to published.
    pub async fn publish(&self, event_id: i32, merch_id: i32) -> Result<Option<()>, AppError> {
        // ADR 0008: soft-deleted rows cannot be republished.
        let affected = sqlx::query(
            "UPDATE merchandise SET status = 'published' \
             WHERE id = $1 AND event_id = $2 AND is_deleted = false",
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
    }

    /// Soft-delete merchandise and cancel affected active matches
    /// (ADR 0008 / ADR 0010 / #423).
    ///
    /// Always sets `is_deleted = true, trade_enabled = false` — never issues
    /// `DELETE FROM merchandise`. In the same transaction, every
    /// `PENDING`/`OFFERED`/`ACCEPTED` match that either has a `match_items`
    /// row for this merch, or is in the merch's event+group with mutual
    /// capacity now zero (legs-less `PENDING` — ADR 0010), is set to
    /// `CANCELLED` with a system `messages` row in the match thread.
    ///
    /// `COMPLETED` matches are left as history. Used by the admin path
    /// (`DELETE /admin/merch/:id`) and by [`Self::delete_merch`] for the
    /// event-scoped creator path.
    ///
    /// Returns `None` if no merchandise row exists for `merch_id`.
    pub async fn delete_by_id(&self, merch_id: i32) -> Result<Option<DeleteOutcome>, AppError> {
        let mut tx = self.pool.begin().await?;

        let row = sqlx::query(
            "SELECT id, event_id, group_name FROM merchandise WHERE id = $1 FOR UPDATE",
        )
        .bind(merch_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        let event_id: i32 = row.get("event_id");
        let group_name: Option<String> = row.get("group_name");

        sqlx::query(
            "UPDATE merchandise SET is_deleted = true, trade_enabled = false WHERE id = $1",
        )
        .bind(merch_id)
        .execute(&mut *tx)
        .await?;

        // ADR 0008 + ADR 0010: cancel matches that reference this merch via
        // match_items, and active matches in the same group whose mutual
        // capacity is now zero (covers legs-less PENDING).
        let matches = MatchRepository::new(self.pool.clone());
        matches
            .cancel_after_merch_delete(
                &mut tx,
                merch_id,
                event_id,
                group_name.as_deref(),
                CANCEL_REASON_MERCH_DELETED,
            )
            .await?;

        tx.commit().await?;
        Ok(Some(DeleteOutcome::SoftDeleted))
    }

    /// Soft-delete merch scoped to an event. Delegates to
    /// [`Self::delete_by_id`]; `event_id` is retained for the event-scoped
    /// route signature used by `merch::delete_merch_by_creator`.
    pub async fn delete_merch(
        &self,
        _event_id: i32,
        merch_id: i32,
    ) -> Result<Option<DeleteOutcome>, AppError> {
        self.delete_by_id(merch_id).await
    }

    /// Fetch the `creator_id` of a merch row, or `None` if the row does
    /// not exist. Used by `delete_merch_by_creator` for the merch-creator
    /// ownership short-circuit (ADR 0004).
    pub async fn get_creator(
        &self,
        event_id: i32,
        merch_id: i32,
    ) -> Result<Option<Option<i32>>, AppError> {
        let row = sqlx::query("SELECT creator_id FROM merchandise WHERE id = $1 AND event_id = $2")
            .bind(merch_id)
            .bind(event_id)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row.map(|r| r.get::<Option<i32>, _>("creator_id")))
    }
}

/// SELECT list for the merch columns in isolation. Use this for INSERT/UPDATE
/// RETURNING paths that don't join to merchandise_groups.
const MERCH_COLUMNS: &str =
    "id, event_id, name, photo_url, group_name, status, is_deleted, trade_enabled, creator_id";

/// SELECT list joined to `merchandise_groups` so each row carries the
/// `group_description` (Issue #128).
const MERCH_SELECT: &str = "m.id, m.event_id, m.name, m.photo_url, m.group_name, m.status, m.is_deleted, m.trade_enabled, m.creator_id, COALESCE(g.description, '') AS group_description";
