//! Outbound match notifications via **Web Push + VAPID** (ADR 0015 / #179).
//!
//! When VAPID is not configured the send path is a safe no-op (log only) so
//! local/CI never call external push services. Delivery failures are logged
//! and never fail match creation.

mod web_push;

pub use web_push::{PushError, SendOutcome, VapidConfig, WebPushSender};

use crate::repositories::push_subscription::PushSubscriptionRepository;
use std::sync::OnceLock;

/// Title shown in the notification shade / OS banner.
pub const MATCH_NOTIFICATION_TITLE: &str = "New match";

/// Body text for a new auto-match / rematch reopen.
pub fn match_notification_body(partner_username: &str) -> String {
    format!("You have a new match with {partner_username}! Check it out in the Trades tab.")
}

/// JSON payload delivered to the service worker `push` event.
pub fn match_notification_payload(partner_username: &str) -> String {
    serde_json::json!({
        "title": MATCH_NOTIFICATION_TITLE,
        "body": match_notification_body(partner_username),
    })
    .to_string()
}

// ---------------------------------------------------------------------------
// Process-global sender (matching background job)
// ---------------------------------------------------------------------------

static SENDER: OnceLock<WebPushSender> = OnceLock::new();

/// Install the process-wide Web Push sender from env (idempotent).
///
/// Call once at process startup. Matching uses [`global_sender`].
pub fn init_from_env() {
    let _ = global_sender();
}

/// Resolve the process-wide sender, initializing from env on first use.
pub fn global_sender() -> &'static WebPushSender {
    SENDER.get_or_init(WebPushSender::from_env)
}

/// Best-effort: load the user's push subscriptions and deliver a match alert.
///
/// Never panics; never returns an error to the caller. On HTTP 404/410 the
/// dead subscription row is deleted so later matches skip it.
pub async fn notify_user_of_match(
    push_subs: &PushSubscriptionRepository,
    sender: &WebPushSender,
    user_id: i32,
    partner_username: &str,
) {
    if !sender.is_enabled() {
        tracing::debug!(
            user_id,
            partner_username,
            "match push skipped (VAPID not configured)"
        );
        return;
    }

    let subs = match push_subs.list_by_user(user_id).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!(
                error = %e,
                user_id,
                "match push: failed to load subscriptions"
            );
            return;
        }
    };

    if subs.is_empty() {
        tracing::debug!(user_id, "match push skipped (no subscriptions)");
        return;
    }

    let payload = match_notification_payload(partner_username);
    for sub in subs {
        match sender.send_to_subscription(&sub, &payload).await {
            Ok(SendOutcome::Delivered) => {
                tracing::info!(
                    user_id,
                    endpoint_host = %endpoint_host(&sub.endpoint),
                    partner_username,
                    "match push delivered"
                );
            }
            Ok(SendOutcome::Gone) => {
                tracing::info!(
                    user_id,
                    endpoint_host = %endpoint_host(&sub.endpoint),
                    "match push endpoint gone; removing subscription"
                );
                if let Err(e) = push_subs.delete_by_endpoint(user_id, &sub.endpoint).await {
                    tracing::warn!(
                        error = %e,
                        user_id,
                        "match push: failed to delete dead subscription"
                    );
                }
            }
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    user_id,
                    endpoint_host = %endpoint_host(&sub.endpoint),
                    partner_username,
                    "match push delivery failed"
                );
            }
        }
    }
}

fn endpoint_host(endpoint: &str) -> String {
    endpoint
        .parse::<axum::http::Uri>()
        .ok()
        .and_then(|u| u.host().map(|h| h.to_string()))
        .unwrap_or_else(|| "unknown".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::repositories::push_subscription::PushSubscriptionRepository;
    use sqlx::PgPool;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    const TEST_VAPID_PRIVATE: &str = "IQ9Ur0ykXoHS9gzfYX0aBjy9lvdrjx_PFUXmie9YRcY";
    const TEST_P256DH: &str =
        "BGa4N1PI79lboMR_YrwCiCsgp35DRvedt7opHcf0yM3iOBTSoQYqQLwWxAfRKE6tsDnReWmhsImkhDF_DBdkNSU";
    const TEST_AUTH: &str = "EvcWjEgzr4rbvhfi3yds0A";

    #[test]
    fn body_includes_partner_and_trades_hint() {
        let body = match_notification_body("alice");
        assert!(body.contains("alice"));
        assert!(body.contains("Trades"));
    }

    #[test]
    fn payload_is_json_with_title_and_body() {
        let raw = match_notification_payload("bob");
        let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(v["title"], MATCH_NOTIFICATION_TITLE);
        assert!(v["body"].as_str().unwrap().contains("bob"));
    }

    #[tokio::test]
    async fn notify_skips_when_vapid_disabled() {
        // No panic / no network when disabled.
        let pool = PgPool::connect_lazy("postgres://unused").unwrap();
        let repo = PushSubscriptionRepository::new(pool);
        let sender = WebPushSender::new(None);
        notify_user_of_match(&repo, &sender, 1, "partner").await;
    }

    #[sqlx::test]
    async fn notify_delivers_and_drops_gone_subscription(pool: PgPool) {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/alive"))
            .respond_with(ResponseTemplate::new(201))
            .expect(1)
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/dead"))
            .respond_with(ResponseTemplate::new(410))
            .expect(1)
            .mount(&server)
            .await;

        let user_id: i32 = sqlx::query_scalar(
            "INSERT INTO users (username, uuid) VALUES ('push-notify-u', 'uuid-push-n') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();

        let repo = PushSubscriptionRepository::new(pool.clone());
        let alive = format!("{}/alive", server.uri());
        let dead = format!("{}/dead", server.uri());
        repo.upsert(user_id, &alive, TEST_P256DH, TEST_AUTH, None)
            .await
            .unwrap();
        repo.upsert(user_id, &dead, TEST_P256DH, TEST_AUTH, None)
            .await
            .unwrap();

        let sender = WebPushSender::new(Some(VapidConfig {
            private_key: TEST_VAPID_PRIVATE.into(),
            subject: "mailto:test@ymatch.local".into(),
        }));
        notify_user_of_match(&repo, &sender, user_id, "partner").await;

        let remaining = repo.list_by_user(user_id).await.unwrap();
        assert_eq!(remaining.len(), 1, "gone endpoint should be removed");
        assert_eq!(remaining[0].endpoint, alive);
    }
}
