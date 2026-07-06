//! RBAC repository — read path for scoped role assignments.
//!
//! [`RbacRepository`] owns the `user_roles` table operations needed by
//! [`crate::services::rbac::RbacService`]. The role/permission *catalog*
//! (which roles exist and which permissions each role grants) is static
//! between migrations, so it is loaded once at startup into the in-memory
//! [`crate::services::permission_catalog::PermissionCatalog`] rather than
//! queried per check. Only `user_roles` — which changes at runtime as
//! roles are assigned/revoked — is queried per authorization decision.
//!
//! See `docs/explanation/adr/0004-rbac-permission-model.md` for the model.
//!
//! PR 2 of #228 adds the read path only (`role_ids_for_user`); the write
//! path (assign/revoke/list members) is added in a later PR alongside the
//! event-member endpoints that consume it.

use crate::error::AppError;
use sqlx::PgPool;

pub struct RbacRepository {
    pool: PgPool,
}

impl RbacRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Return the role ids a user currently holds in the global scope, plus
    /// — when `event_id` is `Some` — the roles they hold scoped to that
    /// specific event. A `None` `event_id` is a pure global-scope check.
    ///
    /// The result feeds [`crate::services::rbac::RbacService::evaluate`],
    /// which maps role ids to permissions via the cached catalog and applies
    /// the admin superuser bypass + `*.any` overlap rule. The global scope
    /// is always included so that a global moderator's `event.edit.any`
    /// permission can satisfy an event-scope `event.edit` check without a
    /// separate query.
    pub async fn role_ids_for_user(
        &self,
        user_id: i32,
        event_id: Option<i32>,
    ) -> Result<Vec<i32>, AppError> {
        let rows = match event_id {
            None => {
                sqlx::query_scalar::<_, i32>(
                    "SELECT role_id FROM user_roles
                     WHERE user_id = $1 AND scope_type = 'global' AND scope_id IS NULL",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await?
            }
            Some(eid) => {
                sqlx::query_scalar::<_, i32>(
                    "SELECT role_id FROM user_roles
                     WHERE user_id = $1
                       AND ((scope_type = 'global' AND scope_id IS NULL)
                            OR (scope_type = 'event' AND scope_id = $2))",
                )
                .bind(user_id)
                .bind(eid)
                .fetch_all(&self.pool)
                .await?
            }
        };
        Ok(rows)
    }
}
