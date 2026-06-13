//! [`PermissionPolicy`] is the single entry point for authentication and
//! authorization decisions in handler code.
//!
//! It is a thin service over [`crate::repositories::user::UserRepository`]
//! plus the policy rules themselves. Handlers depend on this type (not on
//! the repository directly) so the policy rules can evolve without
//! touching every handler.
//!
//! ## Migration from the old `handlers::permissions` module
//!
//! The free functions `get_verified_user`, `require_not_banned`,
//! `check_role`, and `check_ownership_or_role` have been moved here as
//! methods on `PermissionPolicy`. The old module is kept as a thin
//! shim during the Phase 2 migration; it will be removed in Phase 3.

use crate::error::AppError;
use crate::repositories::user::{UserRepository, VerifiedUser};
use std::sync::Arc;

/// Centralized authentication / authorization service.
///
/// Construct once at startup and inject into handler state via
/// `Arc<PermissionPolicy>`. All methods are infallible except for the
/// underlying repository and the policy rules.
#[derive(Clone)]
pub struct PermissionPolicy {
    users: Arc<UserRepository>,
}

impl PermissionPolicy {
    pub fn new(users: Arc<UserRepository>) -> Self {
        Self { users }
    }

    /// Fetch a user and resolve the effective ban state. Returns
    /// `AppError::NotFound` if the user does not exist.
    pub async fn verify(&self, user_id: i32) -> Result<VerifiedUser, AppError> {
        self.users
            .get_verified(user_id)
            .await?
            .ok_or_else(|| AppError::not_found("User not found"))
    }

    /// Reject banned users.
    pub fn require_not_banned(&self, user: &VerifiedUser) -> Result<(), AppError> {
        if user.is_banned {
            Err(AppError::forbidden("User is banned"))
        } else {
            Ok(())
        }
    }

    /// Require one of the listed roles.
    pub fn require_role(
        &self,
        user: &VerifiedUser,
        allowed_roles: &[&str],
    ) -> Result<(), AppError> {
        if allowed_roles.contains(&user.role.as_str()) {
            Ok(())
        } else {
            Err(AppError::forbidden(format!(
                "Requires role: {}",
                allowed_roles.join(" or ")
            )))
        }
    }

    /// Require ownership OR one of the listed elevated roles.
    ///
    /// Use this when the operation is allowed either to the resource owner
    /// or to an admin/moderator. For more complex rules (e.g. "owner OR
    /// event creator OR admin"), compose multiple checks at the call site
    /// — see `merch::delete_merch_by_creator` for the canonical example.
    pub fn require_owner_or_role(
        &self,
        user: &VerifiedUser,
        owner_id: i32,
        elevated_roles: &[&str],
    ) -> Result<(), AppError> {
        if user.id == owner_id {
            return Ok(());
        }
        self.require_role(user, elevated_roles)
    }

    /// Convenience: full `verify + require_not_banned` chain.
    pub async fn verify_active(&self, user_id: i32) -> Result<VerifiedUser, AppError> {
        let user = self.verify(user_id).await?;
        self.require_not_banned(&user)?;
        Ok(user)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::PgPool;
    use std::sync::Arc;

    fn user(id: i32, role: &str, is_banned: bool) -> VerifiedUser {
        VerifiedUser {
            id,
            role: role.to_string(),
            is_banned,
        }
    }

    /// Build a `PermissionPolicy` backed by a lazy `PgPool` for tests
    /// that never call into the repository (the `require_*` methods are
    /// pure). `connect_lazy` does not open a connection, so the URL just
    /// has to be syntactically valid.
    fn policy_lazy() -> PermissionPolicy {
        let pool = PgPool::connect_lazy("postgres://localhost/dummy").unwrap();
        PermissionPolicy::new(Arc::new(UserRepository::new(pool)))
    }

    // --- pure-logic tests (no DB access) ---

    #[tokio::test]
    async fn require_not_banned_allows_active() {
        assert!(
            policy_lazy()
                .require_not_banned(&user(1, "user", false))
                .is_ok()
        );
    }

    #[tokio::test]
    async fn require_not_banned_rejects_banned() {
        let err = policy_lazy()
            .require_not_banned(&user(1, "user", true))
            .unwrap_err();
        assert_eq!(err, AppError::forbidden("User is banned"));
    }

    #[tokio::test]
    async fn require_role_passes_for_allowed() {
        assert!(
            policy_lazy()
                .require_role(&user(1, "admin", false), &["admin", "moderator"])
                .is_ok()
        );
    }

    #[tokio::test]
    async fn require_role_rejects_for_other() {
        let err = policy_lazy()
            .require_role(&user(1, "user", false), &["admin"])
            .unwrap_err();
        match err {
            AppError::Forbidden(msg) => assert!(msg.contains("admin")),
            other => panic!("expected Forbidden, got {:?}", other),
        }
    }

    #[tokio::test]
    async fn require_owner_or_role_owner_passes() {
        // Same user id
        assert!(
            policy_lazy()
                .require_owner_or_role(&user(1, "user", false), 1, &["admin"])
                .is_ok()
        );
    }

    #[tokio::test]
    async fn require_owner_or_role_elevated_passes() {
        // Different user, but admin
        assert!(
            policy_lazy()
                .require_owner_or_role(&user(1, "admin", false), 99, &["admin"])
                .is_ok()
        );
    }

    #[tokio::test]
    async fn require_owner_or_role_other_user_rejected() {
        // Different user, role not in allowed list
        assert!(
            policy_lazy()
                .require_owner_or_role(&user(1, "user", false), 99, &["admin"])
                .is_err()
        );
    }

    // --- DB-backed tests (`#[sqlx::test]` provisions a fresh DB per test) ---

    #[sqlx::test]
    async fn verify_returns_not_found_for_missing_user(pool: PgPool) {
        let users = Arc::new(UserRepository::new(pool));
        let policy = PermissionPolicy::new(users);
        let err = policy.verify(42).await.unwrap_err();
        assert_eq!(err, AppError::not_found("User not found"));
    }

    #[sqlx::test]
    async fn verify_returns_user_when_present(pool: PgPool) {
        sqlx::query("INSERT INTO users (id, username, role) VALUES (1, 'test', 'admin')")
            .execute(&pool)
            .await
            .unwrap();
        let users = Arc::new(UserRepository::new(pool));
        let policy = PermissionPolicy::new(users);
        let u = policy.verify(1).await.unwrap();
        assert_eq!(u.id, 1);
        assert_eq!(u.role, "admin");
    }

    #[sqlx::test]
    async fn verify_active_rejects_banned(pool: PgPool) {
        sqlx::query(
            "INSERT INTO users (id, username, role, is_banned) VALUES (1, 'test', 'user', true)",
        )
        .execute(&pool)
        .await
        .unwrap();
        let users = Arc::new(UserRepository::new(pool));
        let policy = PermissionPolicy::new(users);
        let err = policy.verify_active(1).await.unwrap_err();
        assert_eq!(err, AppError::forbidden("User is banned"));
    }

    #[sqlx::test]
    async fn verify_active_passes_for_active(pool: PgPool) {
        sqlx::query("INSERT INTO users (id, username, role) VALUES (1, 'test', 'user')")
            .execute(&pool)
            .await
            .unwrap();
        let users = Arc::new(UserRepository::new(pool));
        let policy = PermissionPolicy::new(users);
        let u = policy.verify_active(1).await.unwrap();
        assert_eq!(u.id, 1);
    }
}
