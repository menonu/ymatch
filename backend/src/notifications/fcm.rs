//! Firebase Cloud Messaging HTTP v1 client.
//!
//! Auth: service-account JWT → OAuth2 access token (cached until near expiry).
//! Send: `POST /v1/projects/{project_id}/messages:send`.
//!
//! Base URLs are injectable so unit tests can point at a [`wiremock`] server
//! without hitting Google.

use super::{
    MATCH_NOTIFICATION_TITLE, PushError, PushFuture, PushProvider, match_notification_body,
};
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;

const DEFAULT_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const DEFAULT_FCM_BASE: &str = "https://fcm.googleapis.com";
const FCM_SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_REFRESH_SKEW_SECS: u64 = 60;
const MAX_SEND_ATTEMPTS: u32 = 3;
const RETRY_BASE_MS: u64 = 100;
const HTTP_TIMEOUT_SECS: u64 = 5;

/// Google service-account credentials (subset of the standard JSON key file).
#[derive(Clone, Deserialize)]
pub struct ServiceAccount {
    pub client_email: String,
    pub private_key: String,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub token_uri: Option<String>,
}

impl fmt::Debug for ServiceAccount {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ServiceAccount")
            .field("client_email", &self.client_email)
            .field("private_key", &"[redacted]")
            .field("project_id", &self.project_id)
            .field("token_uri", &self.token_uri)
            .finish()
    }
}

/// Runtime configuration for [`FcmPushProvider`].
#[derive(Clone)]
pub struct FcmConfig {
    pub project_id: String,
    pub service_account: ServiceAccount,
    /// OAuth2 token endpoint (override in tests).
    pub token_url: String,
    /// FCM API origin without trailing path (override in tests).
    pub fcm_base_url: String,
}

impl fmt::Debug for FcmConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("FcmConfig")
            .field("project_id", &self.project_id)
            .field("service_account", &self.service_account)
            .field("token_url", &self.token_url)
            .field("fcm_base_url", &self.fcm_base_url)
            .finish()
    }
}

impl FcmConfig {
    /// Load from env. Returns `Ok(None)` when FCM is intentionally disabled
    /// (no project id / no credentials). Returns `Err` on malformed config.
    pub fn from_env() -> Result<Option<Self>, PushError> {
        let project_id = std::env::var("FCM_PROJECT_ID")
            .ok()
            .filter(|s| !s.is_empty());
        let sa_raw = std::env::var("FCM_SERVICE_ACCOUNT_JSON")
            .ok()
            .filter(|s| !s.is_empty())
            .or_else(|| {
                std::env::var("GOOGLE_APPLICATION_CREDENTIALS")
                    .ok()
                    .filter(|s| !s.is_empty())
            });

        match (project_id, sa_raw) {
            (None, None) => Ok(None),
            (Some(_), None) => Err(PushError::Config(
                "FCM_PROJECT_ID is set but no service account credentials found \
                 (FCM_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS)"
                    .into(),
            )),
            (None, Some(raw)) => {
                // Allow project_id from the service-account JSON alone.
                let sa = load_service_account(&raw)?;
                let pid = sa
                    .project_id
                    .clone()
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| {
                        PushError::Config(
                            "service account JSON has no project_id; set FCM_PROJECT_ID".into(),
                        )
                    })?;
                Ok(Some(Self::from_parts(pid, sa)))
            }
            (Some(pid), Some(raw)) => {
                let sa = load_service_account(&raw)?;
                Ok(Some(Self::from_parts(pid, sa)))
            }
        }
    }

    fn from_parts(project_id: String, service_account: ServiceAccount) -> Self {
        let token_url = service_account
            .token_uri
            .clone()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| DEFAULT_TOKEN_URL.to_string());
        Self {
            project_id,
            service_account,
            token_url,
            fcm_base_url: DEFAULT_FCM_BASE.to_string(),
        }
    }
}

fn load_service_account(raw_or_path: &str) -> Result<ServiceAccount, PushError> {
    let json = if raw_or_path.trim_start().starts_with('{') {
        raw_or_path.to_string()
    } else {
        let path = Path::new(raw_or_path);
        std::fs::read_to_string(path).map_err(|e| {
            PushError::Config(format!(
                "failed to read service account file {}: {e}",
                path.display()
            ))
        })?
    };
    serde_json::from_str(&json)
        .map_err(|e| PushError::Config(format!("invalid service account JSON: {e}")))
}

struct CachedToken {
    access_token: String,
    /// UNIX seconds when the token should be considered expired (with skew).
    expires_at: u64,
}

/// FCM HTTP v1 push provider.
pub struct FcmPushProvider {
    http: reqwest::Client,
    config: FcmConfig,
    encoding_key: EncodingKey,
    token_cache: Mutex<Option<CachedToken>>,
}

impl FcmPushProvider {
    pub fn new(config: FcmConfig) -> Result<Self, PushError> {
        let encoding_key = EncodingKey::from_rsa_pem(config.service_account.private_key.as_bytes())
            .map_err(|e| PushError::Config(format!("invalid service account private_key: {e}")))?;
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(HTTP_TIMEOUT_SECS))
            .build()
            .map_err(|e| PushError::Config(format!("failed to build HTTP client: {e}")))?;
        Ok(Self {
            http,
            config,
            encoding_key,
            token_cache: Mutex::new(None),
        })
    }

    /// Test / advanced constructor with a pre-built HTTP client.
    pub fn with_http_client(config: FcmConfig, http: reqwest::Client) -> Result<Self, PushError> {
        let encoding_key = EncodingKey::from_rsa_pem(config.service_account.private_key.as_bytes())
            .map_err(|e| PushError::Config(format!("invalid service account private_key: {e}")))?;
        Ok(Self {
            http,
            config,
            encoding_key,
            token_cache: Mutex::new(None),
        })
    }

    async fn clear_token_cache(&self) {
        *self.token_cache.lock().await = None;
    }

    async fn access_token(&self) -> Result<String, PushError> {
        let now = unix_now();
        {
            let guard = self.token_cache.lock().await;
            if let Some(cached) = guard.as_ref()
                && cached.expires_at > now
            {
                return Ok(cached.access_token.clone());
            }
        }

        let assertion = self.sign_jwt(now)?;
        let resp = self
            .http
            .post(&self.config.token_url)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", assertion.as_str()),
            ])
            .send()
            .await
            .map_err(|e| PushError::Transport(format!("oauth token request failed: {e}")))?;

        let status = resp.status();
        let body = resp
            .text()
            .await
            .map_err(|e| PushError::Transport(format!("oauth token body: {e}")))?;
        if !status.is_success() {
            // 429 / 5xx on the token endpoint are transient (retryable).
            if status.as_u16() == 429 || status.is_server_error() {
                return Err(PushError::Transport(format!(
                    "oauth token retryable HTTP {status}: {body}"
                )));
            }
            return Err(PushError::Provider(format!(
                "oauth token HTTP {status}: {body}"
            )));
        }

        let token_resp: TokenResponse = serde_json::from_str(&body).map_err(|e| {
            PushError::Provider(format!("oauth token JSON parse error: {e}; body={body}"))
        })?;

        let expires_in = token_resp.expires_in.unwrap_or(3600);
        let expires_at = now + expires_in.saturating_sub(TOKEN_REFRESH_SKEW_SECS);
        {
            let mut guard = self.token_cache.lock().await;
            *guard = Some(CachedToken {
                access_token: token_resp.access_token.clone(),
                expires_at,
            });
        }
        Ok(token_resp.access_token)
    }

    fn sign_jwt(&self, now: u64) -> Result<String, PushError> {
        #[derive(Serialize)]
        struct Claims<'a> {
            iss: &'a str,
            scope: &'a str,
            aud: &'a str,
            iat: u64,
            exp: u64,
        }

        let claims = Claims {
            iss: &self.config.service_account.client_email,
            scope: FCM_SCOPE,
            aud: &self.config.token_url,
            iat: now,
            exp: now + 3600,
        };
        let mut header = Header::new(Algorithm::RS256);
        header.typ = Some("JWT".into());
        encode(&header, &claims, &self.encoding_key)
            .map_err(|e| PushError::Config(format!("failed to sign service-account JWT: {e}")))
    }

    async fn send_once(
        &self,
        access_token: &str,
        device_token: &str,
        partner_username: &str,
    ) -> Result<(), PushError> {
        let url = format!(
            "{}/v1/projects/{}/messages:send",
            self.config.fcm_base_url.trim_end_matches('/'),
            self.config.project_id
        );

        let payload = FcmSendRequest {
            message: FcmMessage {
                token: device_token.to_string(),
                notification: FcmNotification {
                    title: MATCH_NOTIFICATION_TITLE.to_string(),
                    body: match_notification_body(partner_username),
                },
            },
        };

        let resp = self
            .http
            .post(&url)
            .bearer_auth(access_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| PushError::Transport(format!("FCM send request failed: {e}")))?;

        let status = resp.status();
        let body = resp
            .text()
            .await
            .map_err(|e| PushError::Transport(format!("FCM send body: {e}")))?;

        if status.is_success() {
            tracing::info!(
                partner_username,
                project_id = %self.config.project_id,
                "match push delivered via FCM"
            );
            return Ok(());
        }

        // Stale/revoked bearer token — clear cache so the next attempt refreshes.
        if status.as_u16() == 401 || status.as_u16() == 403 {
            return Err(PushError::Transport(format!(
                "FCM auth HTTP {status} (will refresh token): {body}"
            )));
        }

        // 429 / 5xx → retryable
        if status.as_u16() == 429 || status.is_server_error() {
            return Err(PushError::Transport(format!(
                "FCM retryable HTTP {status}: {body}"
            )));
        }

        Err(PushError::Provider(format!(
            "FCM rejected message HTTP {status}: {body}"
        )))
    }

    async fn send_with_retries(
        &self,
        device_token: &str,
        partner_username: &str,
    ) -> Result<(), PushError> {
        let mut last_err = PushError::Transport("no attempts".into());
        for attempt in 0..MAX_SEND_ATTEMPTS {
            let token = match self.access_token().await {
                Ok(t) => t,
                Err(e @ PushError::Transport(_)) if attempt + 1 < MAX_SEND_ATTEMPTS => {
                    let delay = Duration::from_millis(RETRY_BASE_MS * 2u64.pow(attempt));
                    tracing::warn!(
                        attempt = attempt + 1,
                        error = %e,
                        "FCM OAuth retrying after transport error"
                    );
                    last_err = e;
                    tokio::time::sleep(delay).await;
                    continue;
                }
                Err(e) => return Err(e),
            };

            match self.send_once(&token, device_token, partner_username).await {
                Ok(()) => return Ok(()),
                Err(e @ PushError::Transport(_)) if attempt + 1 < MAX_SEND_ATTEMPTS => {
                    // Auth failures and other transport errors: drop cached token.
                    self.clear_token_cache().await;
                    let delay = Duration::from_millis(RETRY_BASE_MS * 2u64.pow(attempt));
                    tracing::warn!(
                        attempt = attempt + 1,
                        error = %e,
                        "FCM send retrying after transport error"
                    );
                    last_err = e;
                    tokio::time::sleep(delay).await;
                }
                Err(e) => return Err(e),
            }
        }
        Err(last_err)
    }
}

impl PushProvider for FcmPushProvider {
    fn send_match_notification<'a>(
        &'a self,
        device_token: &'a str,
        partner_username: &'a str,
    ) -> PushFuture<'a, Result<(), PushError>> {
        Box::pin(async move { self.send_with_retries(device_token, partner_username).await })
    }
}

#[derive(Serialize)]
struct FcmSendRequest {
    message: FcmMessage,
}

#[derive(Serialize)]
struct FcmMessage {
    token: String,
    notification: FcmNotification,
}

#[derive(Serialize)]
struct FcmNotification {
    title: String,
    body: String,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    #[serde(default)]
    expires_in: Option<u64>,
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use wiremock::matchers::{body_partial_json, header, method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    // Deterministic RSA key for unit tests only (never a real credential).
    const TEST_PRIVATE_KEY: &str = "-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDtGofanRUX+YXP
5AqDRXpvJEh1C3uZUh6v64V4QRhh3DPUTVo1PnlbAMqNFdE0vExvZCcW2McHIh2P
YHwbRkMJB0r58ezEoMu4gORtaprGB5Oq7IKeO/ls59kHLxWiM56wOn9RARRMGrzl
U9eTvglI4TNuCPIMFPeXawgN2KGdcPZs5IBxSfR4i4oL3hmCBbM6XqWPvAduVOLH
iQDg5XOdnQnSSNs90ld41vo+Sm5daEj5aNminXDCEoYWVIk0VnuDEU24dd17TP4j
wX+f0hQmAW4ifuIMImJd9RmMjjgd2Be7WDrxns7vooYQVK6pPpjVB6Wk0GLcWm83
Dwtn/mRdAgMBAAECggEADDwU/AskgkDyLnTMNRNh+rey1HVT+qih5D6BO+ASB8Sy
2Pbn23z+iptbGFYinjfEMvBGUxe7B2tzfolCRi8FOQNLE2QwLUJF2N6vytSYKXVN
IaIEKHGcUIoTKRt9IIpM2zedh7rIRxgPHL9Ljbhd5siWHIyyHrz7PLE9cGd4CXVo
GH4a90XgLuXJiQxRM6Rn+EazdURmhy9y+ejD7xOp4h/8ofLOAbwjAeyRaHM32Jzq
HUC6po85QDghBKtaXScgNAjtfES+o02tvA9wppVC1AgCIxJzRX7IRPWCUFvSRe5H
yeduqrHLswcB/nAQF02cxGKAuC6KLKINce9o8xR8IQKBgQD4pWXsovClWILmbprk
0jIppG0+hUNERP7YUxSMlfbY1OjMKuwx0i/jxGVoggWSbyZOIDVyNiAnEijM3O//
3g340wegwvf2YzGDktyK4+ZfyVNN7Ry0YU/Cf1ZQLCVWClh5qqpJAtYIE4AVnaSH
3kOwtKjm7OeyBc2Kyz5Sg2ANIQKBgQD0Hb1pcSLAVVkYR/premR+zbPNbZy3dZF0
FjCGZaWdDVYbVBihINToKldjvvwR0sI8sfZDpwPvebh2YIVLF4dCFYX0joWTECKE
Gubogba4j2lvEDoWgc7WnuDaOt73QNHxqY8I9HvMJ0U9rRFZRrwlT8HPYKApZZtm
5E22YHNTvQKBgQCpZrZcVF6zp+v25qAtCXAXouiy0cQUfRVLeL7lUT6OV/ALOasV
/meWPDYCz6LQM13bmGIRYALj26FkgZoZrsXCIrRtuKeLe+U+CQ6sqbxIwjc5PjRy
SGI41tyNXqZJSl8g9T9y4rXDZtW65F42Gx3vBAaW3gy04vM4fmQFf3AvQQKBgQDp
AUH71OsQneZOkNVrpQUrK3iFiixdyDAvl8Z1Yaw0PbiEmT5w/X96on+LS44aDQst
F8gxRscw2wPAqdxQkoKeByE3DppchrgLVAo2vykC/I/sXJa1SO1+WWPRqQONCSfa
/Lb0GzfW41zpw7mddzC6hGg/YsE9AijUivHKNEGgGQKBgEAv8v9jBVhBqKWMuW5B
49OSfgLDu+k5mWGw/CfvM3Jhc3ZaSmy2iChdSODMOUT4XfiGYHR9cjkqYL1Bpzcq
ysURZbrmAcpVwOy3B1JXxjmUTtua/L7ub0j0Z7EQ+DKZcfbc4UrjpsYubtNZwCsP
NcNw2X9hE/FB9y3HqXK0Idc5
-----END PRIVATE KEY-----
";

    fn test_sa() -> ServiceAccount {
        ServiceAccount {
            client_email: "push@test.iam.gserviceaccount.com".into(),
            private_key: TEST_PRIVATE_KEY.into(),
            project_id: Some("ymatch-test".into()),
            token_uri: None,
        }
    }

    fn test_config(server_uri: &str) -> FcmConfig {
        FcmConfig {
            project_id: "ymatch-test".into(),
            service_account: test_sa(),
            token_url: format!("{server_uri}/token"),
            fcm_base_url: server_uri.to_string(),
        }
    }

    async fn mock_oauth(server: &MockServer) {
        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "access_token": "test-access-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            })))
            .mount(server)
            .await;
    }

    #[tokio::test]
    async fn happy_path_sends_fcm_message() {
        let server = MockServer::start().await;
        mock_oauth(&server).await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .and(header("authorization", "Bearer test-access-token"))
            .and(body_partial_json(json!({
                "message": {
                    "token": "device-tok-1",
                    "notification": {
                        "title": "New match",
                        "body": "You have a new match with partner-x! Check it out in the Trades tab."
                    }
                }
            })))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "name": "projects/ymatch-test/messages/0:1"
            })))
            .expect(1)
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        provider
            .send_match_notification("device-tok-1", "partner-x")
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn retries_on_503_then_succeeds() {
        let server = MockServer::start().await;
        mock_oauth(&server).await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .respond_with(ResponseTemplate::new(503).set_body_string("unavailable"))
            .up_to_n_times(1)
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "name": "projects/ymatch-test/messages/0:2"
            })))
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        provider
            .send_match_notification("tok", "retry-partner")
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn non_retryable_4xx_fails_immediately() {
        let server = MockServer::start().await;
        mock_oauth(&server).await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .respond_with(ResponseTemplate::new(400).set_body_string("invalid token"))
            .expect(1)
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        let err = provider
            .send_match_notification("bad-tok", "p")
            .await
            .unwrap_err();
        assert!(matches!(err, PushError::Provider(_)), "{err}");
    }

    #[tokio::test]
    async fn fcm_401_refreshes_token_and_retries() {
        let server = MockServer::start().await;

        // First OAuth → stale-token; second OAuth → fresh-token
        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "access_token": "stale-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            })))
            .up_to_n_times(1)
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "access_token": "fresh-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .and(header("authorization", "Bearer stale-token"))
            .respond_with(ResponseTemplate::new(401).set_body_string("expired"))
            .up_to_n_times(1)
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .and(header("authorization", "Bearer fresh-token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({"name": "m"})))
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        provider
            .send_match_notification("tok", "auth-retry")
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn oauth_503_is_retried() {
        let server = MockServer::start().await;

        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(503).set_body_string("busy"))
            .up_to_n_times(1)
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "access_token": "ok-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            })))
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({"name": "m"})))
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        provider
            .send_match_notification("tok", "oauth-retry")
            .await
            .unwrap();
    }

    #[test]
    fn service_account_debug_redacts_private_key() {
        let sa = test_sa();
        let dbg = format!("{sa:?}");
        assert!(dbg.contains("[redacted]"));
        assert!(!dbg.contains("BEGIN PRIVATE KEY"));
    }

    #[tokio::test]
    async fn oauth_failure_surfaces_as_provider_error() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(401).set_body_string("denied"))
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        let err = provider
            .send_match_notification("tok", "p")
            .await
            .unwrap_err();
        assert!(matches!(err, PushError::Provider(_)), "{err}");
    }

    #[tokio::test]
    async fn access_token_is_cached() {
        let server = MockServer::start().await;

        Mock::given(method("POST"))
            .and(path("/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "access_token": "cached-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            })))
            .expect(1) // only one OAuth call for two sends
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/projects/ymatch-test/messages:send"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({"name": "m"})))
            .expect(2)
            .mount(&server)
            .await;

        let provider = FcmPushProvider::new(test_config(&server.uri())).unwrap();
        provider.send_match_notification("t1", "a").await.unwrap();
        provider.send_match_notification("t2", "b").await.unwrap();
    }

    #[test]
    fn load_service_account_from_inline_json() {
        let json = format!(
            r#"{{
                "client_email": "a@b.com",
                "private_key": {},
                "project_id": "p1"
            }}"#,
            serde_json::to_string(TEST_PRIVATE_KEY).unwrap()
        );
        let sa = load_service_account(&json).unwrap();
        assert_eq!(sa.client_email, "a@b.com");
        assert_eq!(sa.project_id.as_deref(), Some("p1"));
    }

    #[test]
    fn load_service_account_from_file() {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("ymatch-sa-test-{}.json", std::process::id()));
        let json = json!({
            "client_email": "file@b.com",
            "private_key": TEST_PRIVATE_KEY,
            "project_id": "file-proj"
        });
        std::fs::write(&path, json.to_string()).unwrap();
        let sa = load_service_account(path.to_str().unwrap()).unwrap();
        assert_eq!(sa.client_email, "file@b.com");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn invalid_private_key_rejected_at_construct() {
        let mut cfg = test_config("http://127.0.0.1:9");
        cfg.service_account.private_key = "not-a-key".into();
        match FcmPushProvider::new(cfg) {
            Ok(_) => panic!("expected config error for invalid private key"),
            Err(err) => assert!(matches!(err, PushError::Config(_)), "{err}"),
        }
    }
}
