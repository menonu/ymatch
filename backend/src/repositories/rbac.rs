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
//! PR 2 of #228 added the read path (`role_ids_for_user`). PR 3a added the
//! `event/creator` auto-assignment at event creation (ADR 0004 §5). PR 3b
//! adds the member-management write/list path consumed by the event-member
//! endpoints: `assign_event_editor`, `revoke_event_editor`, and
//! `list_event_members`.

use crate::error::AppError;
use crate::generated::ymatch::{EventMember, GroupMember};
use crate::services::rbac::Scope;
use sqlx::{PgConnection, PgPool, Row};

pub struct RbacRepository {
    pool: PgPool,
}

impl RbacRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Return the role ids a user currently holds for the given [`Scope`].
    ///
    /// - [`Scope::Global`]: global roles only.
    /// - [`Scope::Event`]: global + event-scoped roles for that event id.
    /// - [`Scope::Group`]: global + group-scoped roles for that
    ///   `merchandise_groups.id` (#443).
    ///
    /// The result feeds [`crate::services::rbac::RbacService::evaluate`],
    /// which maps role ids to permissions via the cached catalog and applies
    /// the admin superuser bypass + `*.any` overlap rule. The global scope
    /// is always included for event/group checks so a global moderator's
    /// `event.edit.any` (or `group.edit.any`) can satisfy a scoped check
    /// without a separate query.
    pub async fn role_ids_for_user(
        &self,
        user_id: i32,
        scope: &Scope,
    ) -> Result<Vec<i32>, AppError> {
        let rows = match scope {
            Scope::Global => {
                sqlx::query_scalar::<_, i32>(
                    "SELECT role_id FROM user_roles
                     WHERE user_id = $1 AND scope_type = 'global' AND scope_id IS NULL",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await?
            }
            Scope::Event(eid) => {
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
            Scope::Group(gid) => {
                sqlx::query_scalar::<_, i32>(
                    "SELECT role_id FROM user_roles
                     WHERE user_id = $1
                       AND ((scope_type = 'global' AND scope_id IS NULL)
                            OR (scope_type = 'group' AND scope_id = $2))",
                )
                .bind(user_id)
                .bind(gid)
                .fetch_all(&self.pool)
                .await?
            }
        };
        Ok(rows)
    }

    /// Assign the `event/creator` role to `user_id` scoped to `event_id`
    /// (ADR 0004 §5). Called by `events::create_event` inside the same
    /// transaction that inserts the event row, so the creator can edit/publish
    /// their own event (`EventEdit`) and manage its editors
    /// (`EventMemberManage`) without a separate grant step, and the event +
    /// its creator role commit atomically. The catalog also grants
    /// `event.delete` to `event/creator`, which `admin::delete_event` enforces
    /// via `Permission::EventDelete` in `Scope::Event` (#233). Idempotent:
    /// re-running (e.g. on a retry) is a no-op via `ON CONFLICT DO NOTHING`.
    ///
    /// Takes a `&mut PgConnection` from the caller's open transaction so the
    /// role assignment commits with the event row. The role id is looked up
    /// on the same connection so a missing `event/creator` row (unseeded
    /// catalog) surfaces as a 500 here rather than a silent no-op.
    pub async fn assign_event_creator(
        &self,
        exec: &mut PgConnection,
        user_id: i32,
        event_id: i32,
    ) -> Result<(), AppError> {
        let role_id = Self::event_creator_role_id(exec).await?;
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
             VALUES ($1, $2, 'event', $3)
             ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(event_id)
        .execute(&mut *exec)
        .await?;
        Ok(())
    }

    /// Look up the `event/creator` role id on the caller's transaction
    /// connection (so unseeded catalog fails inside the same txn).
    async fn event_creator_role_id(exec: &mut PgConnection) -> Result<i32, AppError> {
        let role_id: i32 = sqlx::query_scalar(
            "SELECT id FROM roles WHERE scope_type = 'event' AND name = 'creator'",
        )
        .fetch_one(&mut *exec)
        .await?;
        Ok(role_id)
    }

    /// Revoke the `event/creator` role from `user_id` for `event_id` (#432).
    /// Used only by the admin event-creator transfer path — the public
    /// members API never removes the creator role. Idempotent: a no-op if
    /// the user does not hold the role.
    pub async fn revoke_event_creator(
        &self,
        exec: &mut PgConnection,
        user_id: i32,
        event_id: i32,
    ) -> Result<(), AppError> {
        let role_id = Self::event_creator_role_id(exec).await?;
        sqlx::query(
            "DELETE FROM user_roles
             WHERE user_id = $1 AND role_id = $2 AND scope_type = 'event' AND scope_id = $3",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(event_id)
        .execute(&mut *exec)
        .await?;
        Ok(())
    }

    /// Atomically transfer the event-scoped `creator` role from
    /// `previous_creator_id` (if any) to `new_creator_id` (#432). Does not
    /// touch `events.creator_id` — the caller updates that column in the same
    /// transaction. Does not auto-grant `editor` to the previous creator.
    pub async fn transfer_event_creator_role(
        &self,
        exec: &mut PgConnection,
        event_id: i32,
        previous_creator_id: Option<i32>,
        new_creator_id: i32,
    ) -> Result<(), AppError> {
        if let Some(prev) = previous_creator_id
            && prev != new_creator_id
        {
            self.revoke_event_creator(exec, prev, event_id).await?;
        }
        self.assign_event_creator(exec, new_creator_id, event_id)
            .await?;
        Ok(())
    }

    /// Look up the `event/<role_name>` role id on the shared pool. Returns
    /// [`AppError::internal`] if the role is missing (unseeded catalog), which
    /// surfaces as a 500 rather than a silent no-op. Shared by the pool-based
    /// member-management write methods.
    async fn event_role_id(&self, role_name: &str) -> Result<i32, AppError> {
        let role_id: i32 =
            sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'event' AND name = $1")
                .bind(role_name)
                .fetch_one(&self.pool)
                .await?;
        Ok(role_id)
    }

    /// Assign the `event/editor` role to `user_id` scoped to `event_id`
    /// (ADR 0004 §5). Used by the event-member API (`POST /events/:id/members`)
    /// which is guarded by `event.member.manage`, so the caller has already
    /// authorized the operation and confirmed the event + target user exist.
    /// Idempotent: re-assigning (e.g. on a retry) is a no-op via
    /// `ON CONFLICT DO NOTHING`. The `creator` role is never assigned here —
    /// only `assign_event_creator` (at event creation) grants that.
    pub async fn assign_event_editor(&self, user_id: i32, event_id: i32) -> Result<(), AppError> {
        let role_id = self.event_role_id("editor").await?;
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
             VALUES ($1, $2, 'event', $3)
             ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(event_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Revoke the `event/editor` role from `user_id` for `event_id` (ADR 0004
    /// §5). Used by the event-member API (`DELETE /events/:id/members/:id`).
    /// Idempotent: revoking a role the user does not hold is a no-op. The
    /// `WHERE` clause filters `role_id` to the `editor` role, so the event
    /// `creator` role is **never** removed here — per the ADR, the creator
    /// role is not removable via this API (only the admin bypass, via a
    /// separate path, can revoke it).
    pub async fn revoke_event_editor(&self, user_id: i32, event_id: i32) -> Result<(), AppError> {
        let role_id = self.event_role_id("editor").await?;
        sqlx::query(
            "DELETE FROM user_roles
             WHERE user_id = $1 AND role_id = $2 AND scope_type = 'event' AND scope_id = $3",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(event_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// List every event-scoped role assignment for `event_id` (ADR 0004 §5).
    /// Used by `GET /events/:id/members`. Returns one [`EventMember`] per
    /// `user_roles` row, joining `users` for the username and `roles` for the
    /// role name. Creators sort before editors (alphabetical role name), then
    /// by user id for stable ordering. The caller must hold
    /// `event.member.manage` (or the admin bypass) — enforced by the handler.
    pub async fn list_event_members(&self, event_id: i32) -> Result<Vec<EventMember>, AppError> {
        let rows = sqlx::query(
            "SELECT u.id AS user_id, u.username, r.name AS role_name
             FROM user_roles ur
             JOIN users u  ON u.id = ur.user_id
             JOIN roles r  ON r.id = ur.role_id
             WHERE ur.scope_type = 'event' AND ur.scope_id = $1
             ORDER BY r.name, u.id",
        )
        .bind(event_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .iter()
            .map(|r| EventMember {
                user_id: r.get("user_id"),
                role: r.get("role_name"),
                username: r.get("username"),
            })
            .collect())
    }

    /// The caller's single event-scoped role on `event_id` (#366), or `None` if
    /// they hold no event role. Used by `GET /events/:id/my-role` to report the
    /// caller's direct membership (`creator` / `editor`) for the frontend role
    /// badge — distinct from the `*.any` / admin-bypass *ability*, which is
    /// reported separately. A user could in principle hold both a `creator`
    /// and `editor` row; `creator` wins (the more privileged role), matching
    /// [`Self::list_event_members`]'s creator-before-editor ordering.
    pub async fn event_role_name(
        &self,
        user_id: i32,
        event_id: i32,
    ) -> Result<Option<String>, AppError> {
        let row: Option<(String,)> = sqlx::query_as(
            "SELECT r.name
             FROM user_roles ur
             JOIN roles r ON r.id = ur.role_id
             WHERE ur.user_id = $1
               AND ur.scope_type = 'event'
               AND ur.scope_id = $2
             ORDER BY CASE r.name WHEN 'creator' THEN 0 WHEN 'editor' THEN 1 ELSE 2 END
             LIMIT 1",
        )
        .bind(user_id)
        .bind(event_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(name,)| name))
    }

    /// The caller's single global role name (`admin` / `moderator` / `user`) if
    /// they hold one (#366), or `None` if unassigned. Used by
    /// `GET /events/:id/my-role` to report `global_override` — whether the
    /// caller's power on the event comes from a global role rather than event
    /// membership. The seeded model assigns at most one global role per user;
    /// `None` covers an unassigned guest.
    pub async fn global_role_name(&self, user_id: i32) -> Result<Option<String>, AppError> {
        let row: Option<(String,)> = sqlx::query_as(
            "SELECT r.name
             FROM user_roles ur
             JOIN roles r ON r.id = ur.role_id
             WHERE ur.user_id = $1 AND ur.scope_type = 'global' AND ur.scope_id IS NULL
             LIMIT 1",
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(name,)| name))
    }

    // --- group scope (#443) -------------------------------------------------

    /// Look up the `group/creator` role id on the caller's transaction
    /// connection (so unseeded catalog fails inside the same txn).
    async fn group_creator_role_id(exec: &mut PgConnection) -> Result<i32, AppError> {
        let role_id: i32 = sqlx::query_scalar(
            "SELECT id FROM roles WHERE scope_type = 'group' AND name = 'creator'",
        )
        .fetch_one(&mut *exec)
        .await?;
        Ok(role_id)
    }

    /// Look up the `group/<role_name>` role id on the shared pool.
    async fn group_role_id(&self, role_name: &str) -> Result<i32, AppError> {
        let role_id: i32 =
            sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = 'group' AND name = $1")
                .bind(role_name)
                .fetch_one(&self.pool)
                .await?;
        Ok(role_id)
    }

    /// Assign the `group/creator` role to `user_id` scoped to
    /// `merchandise_groups.id` (#443). Called at group creation and during
    /// creator transfer. Idempotent via `ON CONFLICT DO NOTHING`.
    pub async fn assign_group_creator(
        &self,
        exec: &mut PgConnection,
        user_id: i32,
        group_id: i32,
    ) -> Result<(), AppError> {
        let role_id = Self::group_creator_role_id(exec).await?;
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
             VALUES ($1, $2, 'group', $3)
             ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(group_id)
        .execute(&mut *exec)
        .await?;
        Ok(())
    }

    /// Revoke the `group/creator` role from `user_id` for `group_id` (#443).
    /// Used only by creator-transfer paths — the public members API never
    /// removes the creator role. Idempotent.
    pub async fn revoke_group_creator(
        &self,
        exec: &mut PgConnection,
        user_id: i32,
        group_id: i32,
    ) -> Result<(), AppError> {
        let role_id = Self::group_creator_role_id(exec).await?;
        sqlx::query(
            "DELETE FROM user_roles
             WHERE user_id = $1 AND role_id = $2 AND scope_type = 'group' AND scope_id = $3",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(group_id)
        .execute(&mut *exec)
        .await?;
        Ok(())
    }

    /// Atomically transfer the group-scoped `creator` role from
    /// `previous_creator_id` (if any) to `new_creator_id` (#443). Does not
    /// touch `merchandise_groups.created_by` — the caller updates that column
    /// in the same transaction. Does not auto-grant `editor` to the previous
    /// creator.
    pub async fn transfer_group_creator_role(
        &self,
        exec: &mut PgConnection,
        group_id: i32,
        previous_creator_id: Option<i32>,
        new_creator_id: i32,
    ) -> Result<(), AppError> {
        if let Some(prev) = previous_creator_id
            && prev != new_creator_id
        {
            self.revoke_group_creator(exec, prev, group_id).await?;
        }
        self.assign_group_creator(exec, new_creator_id, group_id)
            .await?;
        Ok(())
    }

    /// Assign the `group/editor` role to `user_id` scoped to `group_id` (#443).
    /// Idempotent. The `creator` role is never assigned here.
    pub async fn assign_group_editor(&self, user_id: i32, group_id: i32) -> Result<(), AppError> {
        let role_id = self.group_role_id("editor").await?;
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
             VALUES ($1, $2, 'group', $3)
             ON CONFLICT (user_id, role_id, scope_id) DO NOTHING",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(group_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Revoke the `group/editor` role from `user_id` for `group_id` (#443).
    /// Idempotent. Never removes the `creator` role (SQL filters to editor).
    pub async fn revoke_group_editor(&self, user_id: i32, group_id: i32) -> Result<(), AppError> {
        let role_id = self.group_role_id("editor").await?;
        sqlx::query(
            "DELETE FROM user_roles
             WHERE user_id = $1 AND role_id = $2 AND scope_type = 'group' AND scope_id = $3",
        )
        .bind(user_id)
        .bind(role_id)
        .bind(group_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// List every group-scoped role assignment for `group_id` (#443).
    /// Creators sort before editors, then by user id.
    pub async fn list_group_members(&self, group_id: i32) -> Result<Vec<GroupMember>, AppError> {
        let rows = sqlx::query(
            "SELECT u.id AS user_id, u.username, r.name AS role_name
             FROM user_roles ur
             JOIN users u  ON u.id = ur.user_id
             JOIN roles r  ON r.id = ur.role_id
             WHERE ur.scope_type = 'group' AND ur.scope_id = $1
             ORDER BY r.name, u.id",
        )
        .bind(group_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .iter()
            .map(|r| GroupMember {
                user_id: r.get("user_id"),
                role: r.get("role_name"),
                username: r.get("username"),
            })
            .collect())
    }

    /// The caller's single group-scoped role on `group_id` (#443), or `None`.
    /// `creator` wins over `editor` when both rows exist.
    pub async fn group_role_name(
        &self,
        user_id: i32,
        group_id: i32,
    ) -> Result<Option<String>, AppError> {
        let row: Option<(String,)> = sqlx::query_as(
            "SELECT r.name
             FROM user_roles ur
             JOIN roles r ON r.id = ur.role_id
             WHERE ur.user_id = $1
               AND ur.scope_type = 'group'
               AND ur.scope_id = $2
             ORDER BY CASE r.name WHEN 'creator' THEN 0 WHEN 'editor' THEN 1 ELSE 2 END
             LIMIT 1",
        )
        .bind(user_id)
        .bind(group_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(name,)| name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `#[sqlx::test]` provisions a fresh DB with all migrations applied, so
    /// the RBAC catalog (roles/permissions/role_permissions) is already seeded.
    #[sqlx::test]
    async fn event_member_write_path(pool: PgPool) {
        let rbac = RbacRepository::new(pool.clone());

        // Two users; user1 is the event creator, user2 will become an editor.
        for name in ["mem-creator", "mem-editor"] {
            sqlx::query("INSERT INTO users (username) VALUES ($1)")
                .bind(name)
                .execute(&pool)
                .await
                .unwrap();
        }
        let creator_id: i32 =
            sqlx::query_scalar("SELECT id FROM users WHERE username = 'mem-creator'")
                .fetch_one(&pool)
                .await
                .unwrap();
        let editor_id: i32 =
            sqlx::query_scalar("SELECT id FROM users WHERE username = 'mem-editor'")
                .fetch_one(&pool)
                .await
                .unwrap();

        sqlx::query("INSERT INTO events (name, creator_id) VALUES ('Member Event', $1)")
            .bind(creator_id)
            .execute(&pool)
            .await
            .unwrap();
        let event_id: i32 = sqlx::query_scalar("SELECT id FROM events WHERE name = 'Member Event'")
            .fetch_one(&pool)
            .await
            .unwrap();

        // Seed the creator role the way event creation does (assign_event_creator
        // runs inside the event-insert transaction; here the event already exists
        // so we insert the row directly for setup).
        let creator_role_id: i32 = sqlx::query_scalar(
            "SELECT id FROM roles WHERE scope_type = 'event' AND name = 'creator'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
             VALUES ($1, $2, 'event', $3)",
        )
        .bind(creator_id)
        .bind(creator_role_id)
        .bind(event_id)
        .execute(&pool)
        .await
        .unwrap();

        // Initially only the creator is a member.
        let members = rbac.list_event_members(event_id).await.unwrap();
        assert_eq!(members.len(), 1);
        assert_eq!(members[0].user_id, creator_id);
        assert_eq!(members[0].role, "creator");
        assert_eq!(members[0].username.as_deref(), Some("mem-creator"));

        // Assign editor -> two members, creator ordered before editor.
        rbac.assign_event_editor(editor_id, event_id).await.unwrap();
        let members = rbac.list_event_members(event_id).await.unwrap();
        assert_eq!(members.len(), 2);
        assert_eq!(members[0].role, "creator");
        assert_eq!(members[1].role, "editor");
        assert_eq!(members[1].user_id, editor_id);
        assert_eq!(members[1].username.as_deref(), Some("mem-editor"));

        // Idempotent assign: no duplicate row.
        rbac.assign_event_editor(editor_id, event_id).await.unwrap();
        assert_eq!(rbac.list_event_members(event_id).await.unwrap().len(), 2);

        // Revoke editor -> only creator remains.
        rbac.revoke_event_editor(editor_id, event_id).await.unwrap();
        let members = rbac.list_event_members(event_id).await.unwrap();
        assert_eq!(members.len(), 1);
        assert_eq!(members[0].role, "creator");

        // Idempotent revoke: no error, creator still intact.
        rbac.revoke_event_editor(editor_id, event_id).await.unwrap();
        assert_eq!(rbac.list_event_members(event_id).await.unwrap().len(), 1);

        // Revoke targets only the editor role: revoking for the creator (who
        // holds no editor row) does NOT remove their creator role.
        rbac.revoke_event_editor(creator_id, event_id)
            .await
            .unwrap();
        let members = rbac.list_event_members(event_id).await.unwrap();
        assert_eq!(members.len(), 1);
        assert_eq!(members[0].user_id, creator_id);
        assert_eq!(members[0].role, "creator");
    }

    /// Group-scoped member write path (#443): assign/list/revoke editor;
    /// creator is never removed by editor revoke.
    #[sqlx::test]
    async fn group_member_write_path(pool: PgPool) {
        let rbac = RbacRepository::new(pool.clone());

        for name in ["gmem-creator", "gmem-editor"] {
            sqlx::query("INSERT INTO users (username) VALUES ($1)")
                .bind(name)
                .execute(&pool)
                .await
                .unwrap();
        }
        let creator_id: i32 =
            sqlx::query_scalar("SELECT id FROM users WHERE username = 'gmem-creator'")
                .fetch_one(&pool)
                .await
                .unwrap();
        let editor_id: i32 =
            sqlx::query_scalar("SELECT id FROM users WHERE username = 'gmem-editor'")
                .fetch_one(&pool)
                .await
                .unwrap();

        sqlx::query("INSERT INTO events (name, creator_id) VALUES ('GMember Event', $1)")
            .bind(creator_id)
            .execute(&pool)
            .await
            .unwrap();
        let event_id: i32 =
            sqlx::query_scalar("SELECT id FROM events WHERE name = 'GMember Event'")
                .fetch_one(&pool)
                .await
                .unwrap();

        sqlx::query(
            "INSERT INTO merchandise_groups (event_id, group_name, description, created_by)
             VALUES ($1, 'G1', '', $2)",
        )
        .bind(event_id)
        .bind(creator_id)
        .execute(&pool)
        .await
        .unwrap();
        let group_id: i32 = sqlx::query_scalar(
            "SELECT id FROM merchandise_groups WHERE event_id = $1 AND group_name = 'G1'",
        )
        .bind(event_id)
        .fetch_one(&pool)
        .await
        .unwrap();

        let mut tx = pool.begin().await.unwrap();
        rbac.assign_group_creator(&mut tx, creator_id, group_id)
            .await
            .unwrap();
        tx.commit().await.unwrap();

        let members = rbac.list_group_members(group_id).await.unwrap();
        assert_eq!(members.len(), 1);
        assert_eq!(members[0].user_id, creator_id);
        assert_eq!(members[0].role, "creator");

        rbac.assign_group_editor(editor_id, group_id).await.unwrap();
        let members = rbac.list_group_members(group_id).await.unwrap();
        assert_eq!(members.len(), 2);
        assert_eq!(members[0].role, "creator");
        assert_eq!(members[1].role, "editor");
        assert_eq!(members[1].user_id, editor_id);

        rbac.assign_group_editor(editor_id, group_id).await.unwrap();
        assert_eq!(rbac.list_group_members(group_id).await.unwrap().len(), 2);

        rbac.revoke_group_editor(editor_id, group_id).await.unwrap();
        assert_eq!(rbac.list_group_members(group_id).await.unwrap().len(), 1);

        rbac.revoke_group_editor(creator_id, group_id)
            .await
            .unwrap();
        let members = rbac.list_group_members(group_id).await.unwrap();
        assert_eq!(members.len(), 1);
        assert_eq!(members[0].role, "creator");
        assert_eq!(members[0].user_id, creator_id);
    }
}
