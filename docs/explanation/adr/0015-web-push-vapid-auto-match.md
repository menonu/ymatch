# ADR 0015: Background Auto-Match Alerts via Web Push + VAPID

- **Status**: Accepted
- **Date**: 2026-08-10
- **Supersedes**: —
- **Related**: [Issue #179](https://github.com/menonu/ymatch/issues/179). Rejects the earlier FCM HTTP v1 direction (closed PR targeting that approach).

## Context

The periodic matcher creates or reopens `PENDING` trades and already invokes an outbound “match notification” hook for each party. At decision time that hook is a **log-only stub**: users discover new matches only by polling the Trades UI.

Product constraints:

- The shipped client is a **Flutter web** app (desktop browsers, Android Chrome, and iOS **Add to Home Screen** PWA). **Native** Android/iOS apps are out of scope.
- Alerts must work when the tab is **backgrounded or closed** on supported browsers — not only as an in-app toast while focused.
- Match creation must remain reliable: notification delivery is **best-effort** and must never fail or roll back a successful match insert/reopen.
- CI must not depend on live push vendors or real browsers for unit coverage of the send path.

An earlier direction used **FCM HTTP v1** and a single opaque `device_token` on the user row. That fits native SDKs and Firebase-managed tokens, not the Web Push **PushSubscription** shape (endpoint URL + client encryption keys) required by browsers.

## Decision

1. **Protocol and auth.** Deliver background auto-match alerts with the **Web Push** protocol, authenticated with **VAPID** (application server keys). The **public** VAPID key is exposed to the client for `pushManager.subscribe`; the **private** key stays on the server only (env/secret store, never in the public repo).

2. **Client surface.** The Flutter web client (plus a service worker) obtains notification permission, creates a `PushSubscription`, persists it to the API, and handles `push` / `notificationclick` in the service worker. Supported targets: desktop Chromium/Firefox/Edge, Android Chrome (web), and iOS **Home Screen PWA** (best-effort). **Normal iOS Safari tabs** are not a required target.

3. **Subscription storage.** Do **not** overload `users.device_token` for Web Push payloads. Store subscriptions in a **dedicated table** (or equivalent store) keyed by user, with at least endpoint + `p256dh` + `auth` (and usual timestamps). A user may have more than one active subscription (multiple browsers/devices).

4. **Send path.** After auto-create or rematch reopen, the match notification hook loads the parties’ stored subscriptions and attempts Web Push delivery. **Missing config, missing subscriptions, and push HTTP/crypto errors are logged only**; they never fail matching. When VAPID is unset (local/CI default), the sender is a safe no-op (log or skip) and makes **no** external push calls.

5. **Out of product scope for this decision.** Native FCM/APNs, in-app notification center, badges-only UX, email, SMS, guaranteed delivery, and rich marketing push.

6. **Tests.** Unit-test the send path against a **mock** push endpoint (or equivalent), not a live browser push service or third-party account in CI.

## Consequences

**Positive:**

- Background awareness of new matches on the platforms we actually ship (web/PWA).
- Stack matches browser standards; no Firebase dependency for this feature.
- Dedicated subscription rows keep auth guest/`device_token` legacy paths separate from Web Push keys.
- Best-effort semantics preserve matcher reliability and keep local/CI free of vendor credentials.

**Negative / costs:**

- Operators must generate and deploy VAPID key material; misconfiguration silently disables push (by design).
- iOS only works reliably as a Home Screen PWA; that must be documented for users/ops.
- Service worker + permission UX is additional client complexity (subscribe, rotate, unsubscribe, dead-endpoint cleanup).
- Multi-device subscription management and endpoint invalidation (e.g. HTTP 410) need follow-up implementation care.

**Follow-up work (implementation, not this ADR’s decision):**

- Subscription register/unregister API and persistence.
- VAPID-configured Web Push sender wired from the match notification hook.
- Flutter web service worker and permission/subscribe UX.
- How-to: key generation, env vars, iOS PWA install note.

## Alternatives Considered

- **FCM HTTP v1 (or Firebase + APNs) with `device_token`.** Rejected for this product surface: the client is web/PWA only; FCM does not remove the need for Web Push under the hood on browsers and adds a vendor/account dependency we do not want for this feature. Prior FCM-oriented work is closed without merge.

- **In-app only (polling / focused-tab toasts).** Rejected: does not meet the background/closed-tab acceptance goal; matching would remain silent outside an open Trades session.

- **Reuse `users.device_token` as a JSON blob for the PushSubscription.** Rejected: wrong cardinality (one column vs multi-device), poor fit for endpoint rotation/invalidation, and conflates historical FCM-style tokens with Web Push material.

- **Email/SMS for match alerts.** Rejected for this issue: different product surface, cost, and identity requirements; left out of scope.
