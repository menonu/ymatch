//! In-memory catalog of the RBAC role/permission model.
//!
//! [`PermissionCatalog`] is the static half of the RBAC model: the set of
//! roles, the set of permissions, and which permissions each role grants.
//! These tables (`roles`, `permissions`, `role_permissions`) only change via
//! migrations, so the catalog is loaded once at startup
//! ([`PermissionCatalog::load`]) and shared by reference across all
//! authorization decisions. The dynamic half — which roles a *user* holds —
//! lives in `user_roles` and is queried per decision by
//! [`crate::repositories::rbac::RbacRepository`].
//!
//! See `docs/explanation/adr/0004-rbac-permission-model.md`.
//!
//! The [`Self::new`] constructor takes the catalog data directly so the
//! decision logic in [`crate::services::rbac::RbacService::evaluate`] can be
//! unit-tested without a database.

use crate::error::AppError;
use sqlx::PgPool;
use std::collections::{HashMap, HashSet};

/// In-memory snapshot of the `roles` / `permissions` / `role_permissions`
/// catalog, loaded once at startup and read by every authorization decision.
///
/// The catalog is intentionally minimal: it stores the `admin` role id (for
/// the superuser bypass) and a `role_id -> permission-names` map. It does
/// *not* model the `*.any` overlap — that lives in
/// [`crate::services::rbac::Permission::satisfying_names`], which knows which
/// global `*.any` permission satisfies a given event-scope permission. Keeping
/// the overlap out of the catalog means adding a new `*.any` permission is a
/// catalog-row change, not a catalog-structure change.
#[derive(Clone)]
pub struct PermissionCatalog {
    /// The id of the `global/admin` role. A user holding this role passes
    /// every check (the superuser bypass).
    admin_role_id: i32,
    /// `role_id ->` the set of permission names granted to that role.
    permissions_by_role: HashMap<i32, HashSet<String>>,
}

impl PermissionCatalog {
    /// Build a catalog from explicit data. For tests that exercise the
    /// decision logic without a database.
    pub fn new(admin_role_id: i32, permissions_by_role: HashMap<i32, HashSet<String>>) -> Self {
        Self {
            admin_role_id,
            permissions_by_role,
        }
    }

    /// Load the catalog from the seeded `roles` / `permissions` /
    /// `role_permissions` tables. Called once at startup. Returns
    /// [`AppError::internal`] if the catalog has not been seeded (no
    /// `global/admin` role), which is a deployment misconfiguration rather
    /// than a runtime error.
    pub async fn load(pool: &PgPool) -> Result<Self, AppError> {
        let admin_role_id: Option<i32> = sqlx::query_scalar(
            "SELECT id FROM roles WHERE scope_type = 'global' AND name = 'admin'",
        )
        .fetch_optional(pool)
        .await?;
        let admin_role_id = admin_role_id.ok_or_else(|| {
            AppError::internal("RBAC catalog not seeded: global/admin role missing")
        })?;

        // role_id -> permission name, joined to avoid a second round trip.
        let rows: Vec<(i32, String)> = sqlx::query_as(
            "SELECT rp.role_id, p.name
             FROM role_permissions rp
             JOIN permissions p ON p.id = rp.permission_id",
        )
        .fetch_all(pool)
        .await?;

        let mut permissions_by_role: HashMap<i32, HashSet<String>> = HashMap::new();
        for (role_id, perm_name) in rows {
            permissions_by_role
                .entry(role_id)
                .or_default()
                .insert(perm_name);
        }

        Ok(Self {
            admin_role_id,
            permissions_by_role,
        })
    }

    /// The `global/admin` role id. A user holding this role passes every
    /// check via the superuser bypass.
    pub fn admin_role_id(&self) -> i32 {
        self.admin_role_id
    }

    /// True if the given role ids include the global `admin` role — the
    /// superuser bypass.
    pub fn is_admin(&self, role_ids: &[i32]) -> bool {
        role_ids.contains(&self.admin_role_id)
    }

    /// The set of permission names granted by *any* of the given role ids.
    /// Borrowed from the catalog; the caller may iterate without copying.
    pub fn permissions_for_roles<'a>(&'a self, role_ids: &[i32]) -> HashSet<&'a str> {
        let mut out = HashSet::new();
        for rid in role_ids {
            if let Some(perms) = self.permissions_by_role.get(rid) {
                for p in perms {
                    out.insert(p.as_str());
                }
            }
        }
        out
    }
}
