//! Web Push + VAPID delivery (RFC 8030 / RFC 8291 / RFC 8292).
//!
//! Builds encrypted payloads with the `web-push` crate and POSTs them with
//! `reqwest`. HTTP is best-effort; callers log errors and continue.

use crate::repositories::push_subscription::PushSubscription;
use std::fmt;
use std::time::Duration;
use web_push::{
    ContentEncoding, SubscriptionInfo, VapidSignatureBuilder, WebPushMessageBuilder,
    request_builder,
};

const HTTP_TIMEOUT_SECS: u64 = 10;
const DEFAULT_TTL_SECS: u32 = 60 * 60 * 24; // 24h
const DEFAULT_SUBJECT: &str = "mailto:noreply@ymatch.local";

/// Result of a successful HTTP exchange with a push service.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendOutcome {
    /// Push service accepted the message (2xx).
    Delivered,
    /// Endpoint is permanently invalid (404 / 410) — caller should drop the row.
    Gone,
}

/// Errors from building or sending a Web Push message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PushError {
    Config(String),
    Build(String),
    Transport(String),
    Provider(String),
}

impl fmt::Display for PushError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Config(m) => write!(f, "push config: {m}"),
            Self::Build(m) => write!(f, "push build: {m}"),
            Self::Transport(m) => write!(f, "push transport: {m}"),
            Self::Provider(m) => write!(f, "push provider: {m}"),
        }
    }
}

impl std::error::Error for PushError {}

/// VAPID application-server credentials (private key stays server-side only).
#[derive(Clone)]
pub struct VapidConfig {
    /// URL-safe base64 (no padding) raw EC private key bytes.
    pub private_key: String,
    /// `mailto:` or `https:` subject claim required by push services.
    pub subject: String,
}

impl fmt::Debug for VapidConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VapidConfig")
            .field("private_key", &"[redacted]")
            .field("subject", &self.subject)
            .finish()
    }
}

impl VapidConfig {
    /// Load from env. Returns `None` when push is intentionally disabled
    /// (missing private key). Public key is not required for send.
    pub fn from_env() -> Option<Self> {
        let private_key = std::env::var("VAPID_PRIVATE_KEY")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())?;
        let subject = std::env::var("VAPID_SUBJECT")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| DEFAULT_SUBJECT.to_string());
        Some(Self {
            private_key,
            subject,
        })
    }
}

/// Builds and sends Web Push messages when VAPID is configured.
pub struct WebPushSender {
    vapid: Option<VapidConfig>,
    client: reqwest::Client,
}

impl WebPushSender {
    pub fn new(vapid: Option<VapidConfig>) -> Self {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(HTTP_TIMEOUT_SECS))
            // Never follow redirects: a stored HTTPS endpoint must not be able
            // to bounce the server into internal/metadata hosts (SSRF).
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("reqwest client");
        Self { vapid, client }
    }

    /// Construct from `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` env vars.
    pub fn from_env() -> Self {
        let vapid = VapidConfig::from_env();
        if vapid.is_some() {
            tracing::info!("push notifications: Web Push + VAPID sender enabled");
        } else {
            tracing::info!(
                "push notifications: VAPID not configured (set VAPID_PRIVATE_KEY); log-only"
            );
        }
        Self::new(vapid)
    }

    pub fn is_enabled(&self) -> bool {
        self.vapid.is_some()
    }

    /// Encrypt `payload` for `sub` and POST to its endpoint.
    pub async fn send_to_subscription(
        &self,
        sub: &PushSubscription,
        payload: &str,
    ) -> Result<SendOutcome, PushError> {
        let vapid = self
            .vapid
            .as_ref()
            .ok_or_else(|| PushError::Config("VAPID not configured".into()))?;

        let message = build_message(vapid, sub, payload)?;
        post_message(&self.client, message).await
    }
}

fn build_message(
    vapid: &VapidConfig,
    sub: &PushSubscription,
    payload: &str,
) -> Result<web_push::WebPushMessage, PushError> {
    let info = SubscriptionInfo::new(sub.endpoint.clone(), sub.p256dh.clone(), sub.auth.clone());

    let mut sig_builder = VapidSignatureBuilder::from_base64(&vapid.private_key, &info)
        .map_err(|e| PushError::Config(format!("invalid VAPID private key: {e}")))?;
    sig_builder.add_claim("sub", vapid.subject.as_str());
    let signature = sig_builder
        .build()
        .map_err(|e| PushError::Build(format!("VAPID sign failed: {e}")))?;

    let mut builder = WebPushMessageBuilder::new(&info);
    builder.set_ttl(DEFAULT_TTL_SECS);
    builder.set_payload(ContentEncoding::Aes128Gcm, payload.as_bytes());
    builder.set_vapid_signature(signature);
    builder
        .build()
        .map_err(|e| PushError::Build(format!("encrypt/build failed: {e}")))
}

async fn post_message(
    client: &reqwest::Client,
    message: web_push::WebPushMessage,
) -> Result<SendOutcome, PushError> {
    // web-push uses http 0.2; map into reqwest manually.
    let http_req = request_builder::build_request::<Vec<u8>>(message);
    let (parts, body) = http_req.into_parts();
    let url = parts.uri.to_string();
    let method = parts.method.as_str();

    let mut req = client.request(
        reqwest::Method::from_bytes(method.as_bytes())
            .map_err(|e| PushError::Transport(e.to_string()))?,
        &url,
    );
    for (name, value) in parts.headers.iter() {
        let name = name.as_str();
        let value = value
            .to_str()
            .map_err(|e| PushError::Transport(format!("invalid header value: {e}")))?;
        req = req.header(name, value);
    }

    let response = req.body(body).send().await.map_err(|e| {
        // reqwest Display can include the full URL (secret-bearing push path).
        PushError::Transport(e.without_url().to_string())
    })?;

    let status = response.status().as_u16();
    let resp_body = response
        .bytes()
        .await
        .map_err(|e| PushError::Transport(e.without_url().to_string()))?
        .to_vec();

    // Status semantics aligned with web-push `parse_response` (gone → drop sub).
    match status {
        200..=299 => Ok(SendOutcome::Delivered),
        404 | 410 => Ok(SendOutcome::Gone),
        other => {
            let detail = String::from_utf8_lossy(&resp_body);
            Err(PushError::Provider(format!(
                "push service HTTP {other}: {detail}"
            )))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::repositories::push_subscription::PushSubscription;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    /// Known raw EC private key (URL-safe base64) from web-push crate tests.
    const TEST_VAPID_PRIVATE: &str = "IQ9Ur0ykXoHS9gzfYX0aBjy9lvdrjx_PFUXmie9YRcY";
    /// Valid client encryption keys from web-push request_builder tests.
    const TEST_P256DH: &str =
        "BGa4N1PI79lboMR_YrwCiCsgp35DRvedt7opHcf0yM3iOBTSoQYqQLwWxAfRKE6tsDnReWmhsImkhDF_DBdkNSU";
    const TEST_AUTH: &str = "EvcWjEgzr4rbvhfi3yds0A";

    fn test_vapid() -> VapidConfig {
        VapidConfig {
            private_key: TEST_VAPID_PRIVATE.into(),
            subject: "mailto:test@ymatch.local".into(),
        }
    }

    fn sub_for(endpoint: &str) -> PushSubscription {
        PushSubscription {
            id: 1,
            user_id: 1,
            endpoint: endpoint.into(),
            p256dh: TEST_P256DH.into(),
            auth: TEST_AUTH.into(),
            user_agent: None,
        }
    }

    #[test]
    fn vapid_from_env_none_when_unset() {
        // Read-only: unique never-set name is not used; from_env reads fixed names.
        // We only assert constructor path for explicit None.
        let sender = WebPushSender::new(None);
        assert!(!sender.is_enabled());
    }

    #[test]
    fn vapid_config_debug_redacts_private_key() {
        let dbg = format!("{:?}", test_vapid());
        assert!(dbg.contains("[redacted]"));
        assert!(!dbg.contains(TEST_VAPID_PRIVATE));
    }

    #[tokio::test]
    async fn send_posts_encrypted_payload_to_endpoint() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/push"))
            .respond_with(ResponseTemplate::new(201))
            .expect(1)
            .mount(&server)
            .await;

        let endpoint = format!("{}/push", server.uri());
        let sender = WebPushSender::new(Some(test_vapid()));
        let outcome = sender
            .send_to_subscription(&sub_for(&endpoint), r#"{"title":"t","body":"b"}"#)
            .await
            .expect("send ok");
        assert_eq!(outcome, SendOutcome::Delivered);
    }

    #[tokio::test]
    async fn send_maps_410_to_gone() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/dead"))
            .respond_with(ResponseTemplate::new(410))
            .expect(1)
            .mount(&server)
            .await;

        let endpoint = format!("{}/dead", server.uri());
        let sender = WebPushSender::new(Some(test_vapid()));
        let outcome = sender
            .send_to_subscription(&sub_for(&endpoint), "hi")
            .await
            .expect("gone is not hard error");
        assert_eq!(outcome, SendOutcome::Gone);
    }

    #[tokio::test]
    async fn send_maps_404_to_gone() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .respond_with(ResponseTemplate::new(404))
            .expect(1)
            .mount(&server)
            .await;

        let endpoint = format!("{}/missing", server.uri());
        let sender = WebPushSender::new(Some(test_vapid()));
        let outcome = sender
            .send_to_subscription(&sub_for(&endpoint), "hi")
            .await
            .unwrap();
        assert_eq!(outcome, SendOutcome::Gone);
    }

    #[tokio::test]
    async fn send_provider_error_on_4xx() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .respond_with(ResponseTemplate::new(400))
            .expect(1)
            .mount(&server)
            .await;

        let endpoint = format!("{}/bad", server.uri());
        let sender = WebPushSender::new(Some(test_vapid()));
        let err = sender
            .send_to_subscription(&sub_for(&endpoint), "hi")
            .await
            .unwrap_err();
        assert!(matches!(err, PushError::Provider(_)));
    }

    #[tokio::test]
    async fn send_fails_config_when_disabled() {
        let sender = WebPushSender::new(None);
        let err = sender
            .send_to_subscription(&sub_for("https://example.com/p"), "hi")
            .await
            .unwrap_err();
        assert!(matches!(err, PushError::Config(_)));
    }

    #[test]
    fn build_message_rejects_bad_private_key() {
        let vapid = VapidConfig {
            private_key: "not-a-valid-key!!!".into(),
            subject: "mailto:x@y.z".into(),
        };
        let err = build_message(&vapid, &sub_for("https://example.com/p"), "hi").unwrap_err();
        assert!(matches!(err, PushError::Config(_)));
    }
}
