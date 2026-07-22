# ADR 0014: Firebase Cloud Messaging for Match Push Notifications

- **Status**: Accepted
- **Date**: 2026-07-22

## Context

Auto-matching (`matching::run_matching_algorithm`) creates PENDING trades and
calls `notifications::send_match_notification` for each party that has a
`users.device_token`. Until #179 the notification module was a log-only stub, so
users never learned about matches unless they polled the app.

The product needs at least one production push path for the auto-match happy
path. Constraints:

- Flutter clients already accept and store an opaque `device_token` (intended as
  an FCM registration token).
- The backend must remain testable without calling Google (unit tests + CI).
- Missing credentials must not crash local dev or break matching.
- Image storage previously experimented with Firebase/GCS and was removed
  (#458); there is no longer a shared Firebase SDK in-process — only env-based
  credentials are acceptable.

## Decision

Use **Firebase Cloud Messaging HTTP v1** as the sole production push provider:

1. **Auth**: Google service-account JWT → OAuth2 access token (scope
   `https://www.googleapis.com/auth/firebase.messaging`), cached until near
   expiry.
2. **Send**: `POST /v1/projects/{project_id}/messages:send` with a notification
   payload for the match event.
3. **Config** (env, never committed):
   - `FCM_PROJECT_ID`
   - `FCM_SERVICE_ACCOUNT_JSON` (file path or inline JSON), or
     `GOOGLE_APPLICATION_CREDENTIALS` (file path)
4. **Fallback**: when FCM is not configured, install a log-only
   `LoggingPushProvider`. Matching never fails because a push failed.
5. **Testability**: `PushProvider` trait + injectable FCM OAuth/FCM base URLs
   so unit tests drive a mock HTTP server (`wiremock`) instead of Google.

APNs is not integrated directly; iOS delivery goes through FCM when the client
registers an FCM token (standard Flutter `firebase_messaging` path).

## Consequences

- Operators must provision a Firebase project, a service account with FCM
  permissions, and inject credentials into the deploy environment.
- Real end-to-end delivery also requires the Flutter client to obtain and POST
  a real FCM registration token (out of scope for the backend-only #179
  change; tokens already flow via guest/login).
- Push failures are best-effort (warn logs); they do not roll back matches.
- Retry is limited (transient 429/5xx only) to avoid blocking the matching
  loop for long.

## Alternatives Considered

| Option | Why not |
|--------|---------|
| Direct APNs only | iOS-only; still need FCM (or dual stack) for Android/web |
| Legacy FCM server key API | Deprecated; HTTP v1 is the supported path |
| In-app only (WebSocket / SSE) | Valuable stopgap but does not cover background/killed app |
| Defer entirely | Leaves auto-match silent; defeats the matching job's main UX |
