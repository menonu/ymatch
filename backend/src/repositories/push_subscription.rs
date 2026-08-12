//! Push subscription store for Web Push (ADR 0015 / #179).
//!
//! Owns the `push_subscriptions` table. The matching job loads rows by
//! `user_id` when delivering auto-match alerts ([`crate::notifications`]).

use crate::error::AppError;
use sqlx::PgPool;

/// One stored browser `PushSubscription` (endpoint + client keys).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PushSubscription {
    pub id: i32,
    pub user_id: i32,
    pub endpoint: String,
    pub p256dh: String,
    pub auth: String,
    pub user_agent: Option<String>,
}

pub struct PushSubscriptionRepository {
    pool: PgPool,
}

impl PushSubscriptionRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Insert or replace the subscription for `endpoint`.
    ///
    /// On conflict (same endpoint), updates keys and reassigns `user_id` so a
    /// re-login on the same browser does not leave a stale owner.
    pub async fn upsert(
        &self,
        user_id: i32,
        endpoint: &str,
        p256dh: &str,
        auth: &str,
        user_agent: Option<&str>,
    ) -> Result<PushSubscription, AppError> {
        let row = sqlx::query_as::<_, PushSubscriptionRow>(
            r#"
            INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (endpoint) DO UPDATE SET
                user_id = EXCLUDED.user_id,
                p256dh = EXCLUDED.p256dh,
                auth = EXCLUDED.auth,
                user_agent = EXCLUDED.user_agent,
                updated_at = NOW()
            RETURNING id, user_id, endpoint, p256dh, auth, user_agent
            "#,
        )
        .bind(user_id)
        .bind(endpoint)
        .bind(p256dh)
        .bind(auth)
        .bind(user_agent)
        .fetch_one(&self.pool)
        .await?;
        Ok(row.into())
    }

    /// All subscriptions for a user (multi-device).
    pub async fn list_by_user(&self, user_id: i32) -> Result<Vec<PushSubscription>, AppError> {
        let rows = sqlx::query_as::<_, PushSubscriptionRow>(
            r#"
            SELECT id, user_id, endpoint, p256dh, auth, user_agent
            FROM push_subscriptions
            WHERE user_id = $1
            ORDER BY id
            "#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows.into_iter().map(Into::into).collect())
    }

    /// Delete a subscription owned by `user_id` with the given endpoint.
    /// Returns whether a row was removed.
    pub async fn delete_by_endpoint(&self, user_id: i32, endpoint: &str) -> Result<bool, AppError> {
        let affected =
            sqlx::query("DELETE FROM push_subscriptions WHERE user_id = $1 AND endpoint = $2")
                .bind(user_id)
                .bind(endpoint)
                .execute(&self.pool)
                .await?
                .rows_affected();
        Ok(affected > 0)
    }
}

#[derive(sqlx::FromRow)]
struct PushSubscriptionRow {
    id: i32,
    user_id: i32,
    endpoint: String,
    p256dh: String,
    auth: String,
    user_agent: Option<String>,
}

impl From<PushSubscriptionRow> for PushSubscription {
    fn from(r: PushSubscriptionRow) -> Self {
        Self {
            id: r.id,
            user_id: r.user_id,
            endpoint: r.endpoint,
            p256dh: r.p256dh,
            auth: r.auth,
            user_agent: r.user_agent,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[sqlx::test]
    async fn upsert_inserts_and_lists(pool: PgPool) {
        let user_id = insert_user(&pool, "push-upsert-user").await;
        let repo = PushSubscriptionRepository::new(pool);

        let sub = repo
            .upsert(
                user_id,
                "https://push.example/ep-1",
                "p256-key",
                "auth-key",
                Some("TestAgent/1"),
            )
            .await
            .unwrap();

        assert_eq!(sub.user_id, user_id);
        assert_eq!(sub.endpoint, "https://push.example/ep-1");
        assert_eq!(sub.p256dh, "p256-key");
        assert_eq!(sub.auth, "auth-key");
        assert_eq!(sub.user_agent.as_deref(), Some("TestAgent/1"));

        let listed = repo.list_by_user(user_id).await.unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].id, sub.id);
    }

    #[sqlx::test]
    async fn upsert_same_endpoint_updates_and_reassigns(pool: PgPool) {
        let user_a = insert_user(&pool, "push-reassign-a").await;
        let user_b = insert_user(&pool, "push-reassign-b").await;
        let repo = PushSubscriptionRepository::new(pool);

        let first = repo
            .upsert(user_a, "https://push.example/shared", "k1", "a1", None)
            .await
            .unwrap();
        let second = repo
            .upsert(
                user_b,
                "https://push.example/shared",
                "k2",
                "a2",
                Some("Agent/2"),
            )
            .await
            .unwrap();

        assert_eq!(first.id, second.id, "same endpoint keeps one row");
        assert_eq!(second.user_id, user_b);
        assert_eq!(second.p256dh, "k2");
        assert_eq!(second.auth, "a2");
        assert_eq!(second.user_agent.as_deref(), Some("Agent/2"));

        assert!(repo.list_by_user(user_a).await.unwrap().is_empty());
        assert_eq!(repo.list_by_user(user_b).await.unwrap().len(), 1);
    }

    #[sqlx::test]
    async fn delete_by_endpoint_is_owner_scoped(pool: PgPool) {
        let user_a = insert_user(&pool, "push-del-a").await;
        let user_b = insert_user(&pool, "push-del-b").await;
        let repo = PushSubscriptionRepository::new(pool);

        repo.upsert(user_a, "https://push.example/own", "k", "a", None)
            .await
            .unwrap();

        // Other user cannot delete.
        assert!(
            !repo
                .delete_by_endpoint(user_b, "https://push.example/own")
                .await
                .unwrap()
        );
        assert_eq!(repo.list_by_user(user_a).await.unwrap().len(), 1);

        // Owner can delete.
        assert!(
            repo.delete_by_endpoint(user_a, "https://push.example/own")
                .await
                .unwrap()
        );
        assert!(repo.list_by_user(user_a).await.unwrap().is_empty());
    }

    async fn insert_user(pool: &PgPool, username: &str) -> i32 {
        sqlx::query_scalar("INSERT INTO users (username, uuid) VALUES ($1, $2) RETURNING id")
            .bind(username)
            .bind(format!("uuid-{username}"))
            .fetch_one(pool)
            .await
            .unwrap()
    }
}
