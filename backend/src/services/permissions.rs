//! [`PermissionPolicy`] is the authentication + ban-state entry point for
//! handler code.
//!
//! It is a thin service over [`crate::repositories::user::UserRepository`].
//! Handlers depend on this type (not on the repository directly) so the
//! identity/ban rules can evolve without touching every handler.
//!
//! Authorization (role/permission decisions) is handled by
//! [`crate::services::rbac::RbacService`], which checks the `user_roles`
//! source of truth against the [`crate::services::permission_catalog`] model.
//! The old `require_role` / `require_owner_or_role` role-list checks that read
//! the `users.role` denormalized mirror were removed in #370 once every handler
//! had moved to `RbacService::check`; ownership short-circuits live at the
//! handler call site (see `merch::delete_merch_by_creator`).

use crate::error::AppError;
use crate::repositories::user::{UserRepository, VerifiedUser};
use std::sync::Arc;

/// Centralized authentication + ban-state service.
///
/// Construct once at startup and inject into handler state via
/// `Arc<PermissionPolicy>`. All methods are infallible except for the
/// underlying repository.
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
    /// that never call into the repository (`require_not_banned` is pure).
    /// `connect_lazy` does not open a connection, so the URL just has to be
    /// syntactically valid.
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
