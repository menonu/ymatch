//! Outbound push notifications for match events.
//!
//! Production path uses Firebase Cloud Messaging (HTTP v1). When FCM is not
//! configured the process falls back to a logging provider so local/dev and
//! automated tests never attempt real network pushes (ADR 0014).

mod fcm;

pub use fcm::{FcmConfig, FcmPushProvider, ServiceAccount};

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, RwLock};

/// Boxed future returned by [`PushProvider`] methods (dyn-compatible).
pub type PushFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Errors from a push delivery attempt. Matching never fails on these —
/// callers log and continue.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PushError {
    /// Provider misconfiguration or missing credentials at send time.
    Config(String),
    /// Transport / HTTP failure after retries exhausted.
    Transport(String),
    /// FCM (or other provider) rejected the message.
    Provider(String),
}

impl std::fmt::Display for PushError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Config(m) => write!(f, "push config: {m}"),
            Self::Transport(m) => write!(f, "push transport: {m}"),
            Self::Provider(m) => write!(f, "push provider: {m}"),
        }
    }
}

impl std::error::Error for PushError {}

/// Abstraction over the outbound push channel.
///
/// Implementations must be cheap to clone via [`Arc`] and safe to call from
/// the matching background job. Unit tests inject a mock; production uses
/// [`FcmPushProvider`] or [`LoggingPushProvider`].
pub trait PushProvider: Send + Sync {
    fn send_match_notification<'a>(
        &'a self,
        device_token: &'a str,
        partner_username: &'a str,
    ) -> PushFuture<'a, Result<(), PushError>>;
}

/// Log-only provider used when FCM credentials are absent (local dev, CI).
pub struct LoggingPushProvider;

impl PushProvider for LoggingPushProvider {
    fn send_match_notification<'a>(
        &'a self,
        device_token: &'a str,
        partner_username: &'a str,
    ) -> PushFuture<'a, Result<(), PushError>> {
        Box::pin(async move {
            tracing::info!(
                device_token_prefix = %token_prefix(device_token),
                partner_username,
                "match push skipped (no FCM provider configured)"
            );
            Ok(())
        })
    }
}

/// Build the body text shown on the device for a new match.
pub fn match_notification_body(partner_username: &str) -> String {
    format!("You have a new match with {partner_username}! Check it out in the Trades tab.")
}

/// Title shown in the notification shade.
pub const MATCH_NOTIFICATION_TITLE: &str = "New match";

fn token_prefix(token: &str) -> String {
    let take = token.len().min(8);
    format!("{}…", &token[..take])
}

// ---------------------------------------------------------------------------
// Process-global provider (used by matching.rs free-function call site)
// ---------------------------------------------------------------------------

/// Interior mutability so tests can swap providers; production sets once at boot.
static PROVIDER: RwLock<Option<Arc<dyn PushProvider>>> = RwLock::new(None);

/// Install the process-wide push provider (overwrites any previous value).
pub fn set_provider(provider: Arc<dyn PushProvider>) {
    *PROVIDER.write().expect("push provider lock poisoned") = Some(provider);
}

/// Resolve the active provider, defaulting to [`LoggingPushProvider`].
pub fn provider() -> Arc<dyn PushProvider> {
    PROVIDER
        .read()
        .expect("push provider lock poisoned")
        .clone()
        .unwrap_or_else(|| Arc::new(LoggingPushProvider))
}

/// Configure the global provider from environment variables.
///
/// When `FCM_PROJECT_ID` and service-account credentials are present, installs
/// [`FcmPushProvider`]. Otherwise installs [`LoggingPushProvider`] and logs a
/// single info line so operators know pushes are disabled.
///
/// Credential sources (first match wins):
/// 1. `FCM_SERVICE_ACCOUNT_JSON` — path to a service-account JSON file, or the
///    raw JSON document itself
/// 2. `GOOGLE_APPLICATION_CREDENTIALS` — path to a service-account JSON file
pub fn init_from_env() {
    match FcmConfig::from_env() {
        Ok(Some(config)) => match FcmPushProvider::new(config) {
            Ok(fcm) => {
                tracing::info!("push notifications: FCM HTTP v1 provider enabled");
                set_provider(Arc::new(fcm));
            }
            Err(e) => {
                tracing::error!(
                    error = %e,
                    "push notifications: failed to build FCM provider; using log-only fallback"
                );
                set_provider(Arc::new(LoggingPushProvider));
            }
        },
        Ok(None) => {
            tracing::info!(
                "push notifications: FCM not configured (set FCM_PROJECT_ID + credentials); log-only"
            );
            set_provider(Arc::new(LoggingPushProvider));
        }
        Err(e) => {
            tracing::error!(
                error = %e,
                "push notifications: invalid FCM config; using log-only fallback"
            );
            set_provider(Arc::new(LoggingPushProvider));
        }
    }
}

/// Send a match notification via the process-global provider.
///
/// Errors are logged; this never panics. Matching must not fail because a
/// push delivery failed.
pub async fn send_match_notification(device_token: &str, partner_username: &str) {
    if device_token.is_empty() {
        tracing::debug!("match push skipped: empty device_token");
        return;
    }
    if let Err(e) = provider()
        .send_match_notification(device_token, partner_username)
        .await
    {
        tracing::warn!(
            error = %e,
            device_token_prefix = %token_prefix(device_token),
            partner_username,
            "failed to send match push notification"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct RecordingProvider {
        calls: Mutex<Vec<(String, String)>>,
        fail: bool,
    }

    impl PushProvider for RecordingProvider {
        fn send_match_notification<'a>(
            &'a self,
            device_token: &'a str,
            partner_username: &'a str,
        ) -> PushFuture<'a, Result<(), PushError>> {
            Box::pin(async move {
                self.calls
                    .lock()
                    .unwrap()
                    .push((device_token.to_string(), partner_username.to_string()));
                if self.fail {
                    Err(PushError::Provider("forced".into()))
                } else {
                    Ok(())
                }
            })
        }
    }

    #[test]
    fn match_body_includes_partner_name() {
        let body = match_notification_body("alice");
        assert!(body.contains("alice"));
        assert!(body.contains("Trades tab"));
    }

    #[tokio::test]
    async fn free_function_forwards_to_provider() {
        let recorder = Arc::new(RecordingProvider {
            calls: Mutex::new(Vec::new()),
            fail: false,
        });
        set_provider(recorder.clone());
        send_match_notification("token-abc", "bob").await;
        let calls = recorder.calls.lock().unwrap().clone();
        assert_eq!(calls, vec![("token-abc".into(), "bob".into())]);
    }

    #[tokio::test]
    async fn free_function_swallows_provider_errors() {
        let recorder = Arc::new(RecordingProvider {
            calls: Mutex::new(Vec::new()),
            fail: true,
        });
        set_provider(recorder.clone());
        // Must not panic; free function logs and returns unit.
        send_match_notification("tok", "carol").await;
        assert_eq!(recorder.calls.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn logging_provider_succeeds() {
        let p = LoggingPushProvider;
        p.send_match_notification("deadbeef-token", "dave")
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn empty_token_is_noop_on_free_function() {
        let hits = Arc::new(AtomicUsize::new(0));
        struct CountingProvider {
            hits: Arc<AtomicUsize>,
        }
        impl PushProvider for CountingProvider {
            fn send_match_notification<'a>(
                &'a self,
                _device_token: &'a str,
                _partner_username: &'a str,
            ) -> PushFuture<'a, Result<(), PushError>> {
                Box::pin(async move {
                    self.hits.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                })
            }
        }
        set_provider(Arc::new(CountingProvider { hits: hits.clone() }));
        send_match_notification("", "eve").await;
        assert_eq!(hits.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn set_provider_is_used_by_free_function() {
        let hits = Arc::new(AtomicUsize::new(0));
        struct CountingProvider {
            hits: Arc<AtomicUsize>,
        }
        impl PushProvider for CountingProvider {
            fn send_match_notification<'a>(
                &'a self,
                _device_token: &'a str,
                _partner_username: &'a str,
            ) -> PushFuture<'a, Result<(), PushError>> {
                Box::pin(async move {
                    self.hits.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                })
            }
        }
        set_provider(Arc::new(CountingProvider { hits: hits.clone() }));
        send_match_notification("tok-1", "frank").await;
        assert_eq!(hits.load(Ordering::SeqCst), 1);
    }
}
