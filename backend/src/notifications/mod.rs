//! Outbound trade notifications via **Web Push + VAPID** (ADR 0015 / #179 / #577).
//!
//! Events: auto-match, incoming offer (including counter), offer accepted, and
//! chat message. When VAPID is not configured the send path is a safe no-op
//! (log only) so local/CI never call external push services. Delivery failures
//! are logged and never fail match / offer / accept / send.

mod web_push;

pub use web_push::{PushError, SendOutcome, VapidConfig, WebPushSender};

use crate::repositories::push_subscription::PushSubscriptionRepository;
use crate::repositories::user::UserRepository;
use sqlx::PgPool;
use std::sync::OnceLock;

/// Title shown in the notification shade / OS banner.
pub const MATCH_NOTIFICATION_TITLE: &str = "New match";
pub const OFFER_NOTIFICATION_TITLE: &str = "New offer";
pub const ACCEPTED_NOTIFICATION_TITLE: &str = "Offer accepted";
pub const MESSAGE_NOTIFICATION_TITLE: &str = "New message";

const MATCHES_PATH: &str = "/matches";
const MESSAGE_PREVIEW_MAX_CHARS: usize = 80;

/// Body text for a new auto-match / rematch reopen.
pub fn match_notification_body(partner_username: &str) -> String {
    format!("You have a new match with {partner_username}! Check it out in the Trades tab.")
}

/// JSON payload delivered to the service worker `push` event.
pub fn match_notification_payload(partner_username: &str) -> String {
    push_payload(
        MATCH_NOTIFICATION_TITLE,
        &match_notification_body(partner_username),
        MATCHES_PATH,
    )
}

/// Deep-link into the trade chat for offer / accept / message alerts (#577).
pub fn trade_chat_path(match_id: i32) -> String {
    format!("/matches/chat/{match_id}")
}

pub fn offer_received_body(actor_username: &str) -> String {
    format!("{actor_username} sent you an offer. Open the trade to review it.")
}

pub fn offer_received_payload(actor_username: &str, match_id: i32) -> String {
    push_payload(
        OFFER_NOTIFICATION_TITLE,
        &offer_received_body(actor_username),
        &trade_chat_path(match_id),
    )
}

pub fn offer_accepted_body(actor_username: &str) -> String {
    format!("{actor_username} accepted your offer.")
}

pub fn offer_accepted_payload(actor_username: &str, match_id: i32) -> String {
    push_payload(
        ACCEPTED_NOTIFICATION_TITLE,
        &offer_accepted_body(actor_username),
        &trade_chat_path(match_id),
    )
}

pub fn message_received_body(
    actor_username: &str,
    message_type: Option<&str>,
    content: &str,
) -> String {
    if is_location_share(message_type, content) {
        return format!("{actor_username} shared a location");
    }
    let preview = truncate_preview(content);
    if preview.is_empty() {
        format!("{actor_username} sent a message")
    } else {
        format!("{actor_username}: {preview}")
    }
}

/// Chat location share is often TEXT + a maps URL (the Flutter client does
/// not set `message_type: LOCATION`). Redact both shapes so coordinates
/// never appear on the OS banner (#577 review).
fn is_location_share(message_type: Option<&str>, content: &str) -> bool {
    if message_type == Some("LOCATION") {
        return true;
    }
    let lower = content.to_ascii_lowercase();
    lower.contains("maps.app.goo.gl")
        || lower.contains("google.com/maps")
        || lower.contains("maps.apple.com")
}

pub fn message_received_payload(
    actor_username: &str,
    match_id: i32,
    message_type: Option<&str>,
    content: &str,
) -> String {
    push_payload(
        MESSAGE_NOTIFICATION_TITLE,
        &message_received_body(actor_username, message_type, content),
        &trade_chat_path(match_id),
    )
}

fn push_payload(title: &str, body: &str, path: &str) -> String {
    serde_json::json!({
        "title": title,
        "body": body,
        "path": path,
    })
    .to_string()
}

fn truncate_preview(content: &str) -> String {
    let collapsed = content.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut chars = collapsed.chars();
    let taken: String = chars.by_ref().take(MESSAGE_PREVIEW_MAX_CHARS).collect();
    if chars.next().is_some() {
        format!("{taken}…")
    } else {
        taken
    }
}

/// The participant who is not `actor_id`.
pub fn other_participant(user1_id: i32, user2_id: i32, actor_id: i32) -> i32 {
    if actor_id == user1_id {
        user2_id
    } else {
        user1_id
    }
}

// ---------------------------------------------------------------------------
// Process-global sender (matching background job + request-path hooks)
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

/// Fire-and-forget: load the actor's username and notify the other party.
///
/// Never fails the caller. Skips when `recipient_id == actor_id`.
pub fn schedule_notify_from_actor<F>(
    pool: PgPool,
    recipient_id: i32,
    actor_id: i32,
    kind: &'static str,
    build_payload: F,
) where
    F: FnOnce(&str) -> String + Send + 'static,
{
    tokio::spawn(async move {
        notify_from_actor(
            &pool,
            global_sender(),
            recipient_id,
            actor_id,
            kind,
            build_payload,
        )
        .await;
    });
}

/// Best-effort: resolve actor username, then deliver `build_payload(username)`.
///
/// Never panics; never returns an error to the caller. Tests pass an
/// explicit [`WebPushSender`]; production uses [`global_sender`].
pub async fn notify_from_actor<F>(
    pool: &PgPool,
    sender: &WebPushSender,
    recipient_id: i32,
    actor_id: i32,
    kind: &'static str,
    build_payload: F,
) where
    F: FnOnce(&str) -> String,
{
    if recipient_id == actor_id {
        tracing::debug!(recipient_id, kind, "push skipped (actor is recipient)");
        return;
    }

    let users = UserRepository::new(pool.clone());
    let actor = match users.get_by_id(actor_id).await {
        Ok(Some(u)) => u,
        Ok(None) => {
            tracing::debug!(actor_id, kind, "push skipped (actor not found)");
            return;
        }
        Err(e) => {
            tracing::warn!(error = %e, actor_id, kind, "push: failed to load actor");
            return;
        }
    };

    let payload = build_payload(&actor.username);
    let push_subs = PushSubscriptionRepository::new(pool.clone());
    notify_user(&push_subs, sender, recipient_id, &payload, kind).await;
}

/// Best-effort: load the user's push subscriptions and deliver `payload`.
///
/// Never panics; never returns an error to the caller. On HTTP 404/410 the
/// dead subscription row is deleted so later events skip it.
pub async fn notify_user(
    push_subs: &PushSubscriptionRepository,
    sender: &WebPushSender,
    user_id: i32,
    payload: &str,
    kind: &str,
) {
    if !sender.is_enabled() {
        tracing::debug!(user_id, kind, "push skipped (VAPID not configured)");
        return;
    }

    let subs = match push_subs.list_by_user(user_id).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!(error = %e, user_id, kind, "push: failed to load subscriptions");
            return;
        }
    };

    if subs.is_empty() {
        tracing::debug!(user_id, kind, "push skipped (no subscriptions)");
        return;
    }

    for sub in subs {
        match sender.send_to_subscription(&sub, payload).await {
            Ok(SendOutcome::Delivered) => {
                tracing::info!(
                    user_id,
                    kind,
                    endpoint_host = %endpoint_host(&sub.endpoint),
                    "push delivered"
                );
            }
            Ok(SendOutcome::Gone) => {
                tracing::info!(
                    user_id,
                    kind,
                    endpoint_host = %endpoint_host(&sub.endpoint),
                    "push endpoint gone; removing subscription"
                );
                if let Err(e) = push_subs.delete_by_endpoint(user_id, &sub.endpoint).await {
                    tracing::warn!(
                        error = %e,
                        user_id,
                        kind,
                        "push: failed to delete dead subscription"
                    );
                }
            }
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    user_id,
                    kind,
                    endpoint_host = %endpoint_host(&sub.endpoint),
                    "push delivery failed"
                );
            }
        }
    }
}

/// Best-effort match alert. Wrapper around [`notify_user`] for the matcher.
pub async fn notify_user_of_match(
    push_subs: &PushSubscriptionRepository,
    sender: &WebPushSender,
    user_id: i32,
    partner_username: &str,
) {
    let payload = match_notification_payload(partner_username);
    notify_user(push_subs, sender, user_id, &payload, "match").await;
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

    fn parse_payload(raw: &str) -> serde_json::Value {
        serde_json::from_str(raw).unwrap()
    }

    #[test]
    fn body_includes_partner_and_trades_hint() {
        let body = match_notification_body("alice");
        assert!(body.contains("alice"));
        assert!(body.contains("Trades"));
    }

    #[test]
    fn match_payload_is_json_with_title_body_and_path() {
        let v = parse_payload(&match_notification_payload("bob"));
        assert_eq!(v["title"], MATCH_NOTIFICATION_TITLE);
        assert!(v["body"].as_str().unwrap().contains("bob"));
        assert_eq!(v["path"], MATCHES_PATH);
    }

    #[test]
    fn offer_payload_names_actor_and_opens_chat() {
        let v = parse_payload(&offer_received_payload("alice", 42));
        assert_eq!(v["title"], OFFER_NOTIFICATION_TITLE);
        assert!(v["body"].as_str().unwrap().contains("alice"));
        assert_eq!(v["path"], "/matches/chat/42");
    }

    #[test]
    fn accepted_payload_names_actor_and_opens_chat() {
        let v = parse_payload(&offer_accepted_payload("bob", 7));
        assert_eq!(v["title"], ACCEPTED_NOTIFICATION_TITLE);
        assert!(v["body"].as_str().unwrap().contains("bob"));
        assert!(v["body"].as_str().unwrap().contains("accepted"));
        assert_eq!(v["path"], "/matches/chat/7");
    }

    #[test]
    fn message_payload_includes_preview_and_opens_chat() {
        let v = parse_payload(&message_received_payload(
            "alice",
            9,
            Some("TEXT"),
            "hello there",
        ));
        assert_eq!(v["title"], MESSAGE_NOTIFICATION_TITLE);
        assert_eq!(v["body"], "alice: hello there");
        assert_eq!(v["path"], "/matches/chat/9");
    }

    #[test]
    fn message_payload_location_type_does_not_leak_coordinates() {
        let body = message_received_body("alice", Some("LOCATION"), "35.0,139.0");
        assert_eq!(body, "alice shared a location");
        assert!(!body.contains("35.0"));
    }

    #[test]
    fn message_payload_maps_url_text_does_not_leak_coordinates() {
        // Shipped chat client sends location as TEXT + Google Maps URL.
        let url = "https://www.google.com/maps/search/?api=1&query=35.0,139.0";
        for message_type in [None, Some("TEXT")] {
            let body = message_received_body("alice", message_type, url);
            assert_eq!(body, "alice shared a location");
            assert!(!body.contains("35.0"));
            assert!(!body.contains("139.0"));
            assert!(!body.contains("maps"));
        }
    }

    #[test]
    fn message_preview_truncates_long_text() {
        let long = "a".repeat(120);
        let body = message_received_body("bob", Some("TEXT"), &long);
        assert!(body.starts_with("bob: "));
        assert!(body.ends_with('…'));
        assert!(body.chars().count() < 120);
    }

    #[test]
    fn other_participant_picks_the_non_actor() {
        assert_eq!(other_participant(1, 2, 1), 2);
        assert_eq!(other_participant(1, 2, 2), 1);
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
    async fn notify_from_actor_skips_when_recipient_is_actor(pool: PgPool) {
        let user_id: i32 = sqlx::query_scalar(
            "INSERT INTO users (username, uuid) VALUES ('self-push', 'uuid-self-push') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();

        // Would panic if a payload builder ran; skip must not call it.
        let sender = WebPushSender::new(None);
        notify_from_actor(&pool, &sender, user_id, user_id, "offer", |_| {
            panic!("must not build payload for self-notify")
        })
        .await;
    }

    #[sqlx::test]
    async fn notify_from_actor_loads_username_and_delivers(pool: PgPool) {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/from-actor"))
            .respond_with(ResponseTemplate::new(201))
            .expect(1)
            .mount(&server)
            .await;

        let actor_id: i32 = sqlx::query_scalar(
            "INSERT INTO users (username, uuid) VALUES ('alice-actor', 'uuid-actor') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        let recipient_id: i32 = sqlx::query_scalar(
            "INSERT INTO users (username, uuid) VALUES ('bob-recip', 'uuid-recip') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();

        let repo = PushSubscriptionRepository::new(pool.clone());
        let endpoint = format!("{}/from-actor", server.uri());
        repo.upsert(recipient_id, &endpoint, TEST_P256DH, TEST_AUTH, None)
            .await
            .unwrap();

        let sender = WebPushSender::new(Some(VapidConfig {
            private_key: TEST_VAPID_PRIVATE.into(),
            subject: "mailto:test@ymatch.local".into(),
        }));
        notify_from_actor(
            &pool,
            &sender,
            recipient_id,
            actor_id,
            "offer",
            |username| offer_received_payload(username, 11),
        )
        .await;
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

    #[sqlx::test]
    async fn notify_user_delivers_offer_payload(pool: PgPool) {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/offer"))
            .respond_with(ResponseTemplate::new(201))
            .expect(1)
            .mount(&server)
            .await;

        let user_id: i32 = sqlx::query_scalar(
            "INSERT INTO users (username, uuid) VALUES ('push-offer-u', 'uuid-push-o') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();

        let repo = PushSubscriptionRepository::new(pool.clone());
        let endpoint = format!("{}/offer", server.uri());
        repo.upsert(user_id, &endpoint, TEST_P256DH, TEST_AUTH, None)
            .await
            .unwrap();

        let sender = WebPushSender::new(Some(VapidConfig {
            private_key: TEST_VAPID_PRIVATE.into(),
            subject: "mailto:test@ymatch.local".into(),
        }));
        let payload = offer_received_payload("alice", 11);
        notify_user(&repo, &sender, user_id, &payload, "offer").await;
    }
}
