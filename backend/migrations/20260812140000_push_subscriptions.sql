-- #179 / ADR 0015: Web Push subscription store (endpoint + encryption keys).
-- Separate from users.device_token (legacy FCM-style single token).
-- A user may have multiple subscriptions (multiple browsers/devices).
-- endpoint is unique globally: re-subscribe reassigns the row to the current user.

CREATE TABLE IF NOT EXISTS push_subscriptions (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    endpoint    TEXT NOT NULL,
    p256dh      TEXT NOT NULL,
    auth        TEXT NOT NULL,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint)
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id
    ON push_subscriptions (user_id);
