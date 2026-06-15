//! Shared row-mapper helpers used by handlers and (in later phases) repositories.
//!
//! These are promoted from file-private `*_from_row` functions in `auth.rs`,
//! `merch.rs`, and `groups.rs` to a single, discoverable location. They are
//! `pub` so repositories (Phase 2-5) can call them when assembling domain
//! objects from query results.
//!
//! All mappers take `&sqlx::postgres::PgRow` and are tolerant of optional
//! columns. Empty strings from `TEXT NOT NULL DEFAULT ''` columns are
//! converted to `None` for proto3 `optional string` fields, which is the
//! convention the proto schema relies on.

use crate::generated::ymatch::{Merchandise, MerchandiseGroup, User};
use chrono::{DateTime, Utc};
use sqlx::Row;

/// Format a `DateTime<Utc>` as an RFC3339 string, mirroring the proto3
/// convention used by the existing handlers. Returns `None` for `None`.
pub fn to_rfc3339(dt: Option<DateTime<Utc>>) -> Option<String> {
    dt.map(|d| d.to_rfc3339())
}

/// Empty string -> `None`. Used to normalize `TEXT NOT NULL DEFAULT ''`
/// columns to the proto3 `optional string` shape.
pub fn empty_to_none(s: Option<String>) -> Option<String> {
    s.filter(|v| !v.is_empty())
}

/// Map a `users` table row to the [`User`] proto message.
///
/// Required columns: `id, username, uuid, device_token, created_at, role,
/// is_banned, ban_reason, banned_until`. `password_hash` is intentionally
/// NOT included here; auth handlers that need it select it explicitly and
/// drop it before calling this mapper (or return their own type).
pub fn user_from_row(row: &sqlx::postgres::PgRow) -> User {
    User {
        id: row.get("id"),
        username: row.get("username"),
        uuid: row.get("uuid"),
        device_token: row.get("device_token"),
        created_at: to_rfc3339(row.get("created_at")),
        role: row.get("role"),
        is_banned: row.get("is_banned"),
        ban_reason: row.get("ban_reason"),
        banned_until: to_rfc3339(row.get("banned_until")),
    }
}

/// Map a `merchandise` row to [`Merchandise`].
///
/// If the SELECT includes a `group_description` column (e.g. from a LEFT JOIN
/// to `merchandise_groups`), the value is read and returned in
/// [`Merchandise::group_description`]. Empty strings are normalized to
/// `None` to match the proto3 `optional string` convention.
pub fn merch_from_row(row: &sqlx::postgres::PgRow) -> Merchandise {
    let group_description: Option<String> = row
        .try_get::<Option<String>, _>("group_description")
        .ok()
        .flatten()
        .or_else(|| row.try_get::<String, _>("group_description").ok());
    Merchandise {
        id: row.get("id"),
        event_id: row.get("event_id"),
        name: row.get("name"),
        photo_url: row.get("photo_url"),
        group_name: row.get("group_name"),
        status: Some(row.get("status")),
        is_deleted: Some(row.get("is_deleted")),
        trade_enabled: row.get("trade_enabled"),
        creator_id: row.get("creator_id"),
        group_description: empty_to_none(group_description),
    }
}

/// Map a `merchandise_groups` row to [`MerchandiseGroup`].
pub fn group_from_row(row: &sqlx::postgres::PgRow) -> MerchandiseGroup {
    MerchandiseGroup {
        id: row.get("id"),
        event_id: row.get("event_id"),
        group_name: row.get("group_name"),
        description: empty_to_none(row.get("description")),
        created_by: row.get("created_by"),
        created_at: to_rfc3339(row.get("created_at")),
        updated_at: to_rfc3339(row.get("updated_at")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn to_rfc3339_none_passes_through() {
        assert_eq!(to_rfc3339(None), None);
    }

    #[test]
    fn to_rfc3339_formats_utc() {
        let dt: DateTime<Utc> = DateTime::parse_from_rfc3339("2026-06-09T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let s = to_rfc3339(Some(dt)).unwrap();
        assert!(s.starts_with("2026-06-09T12:00:00"));
    }

    #[test]
    fn empty_to_none_treats_empty_as_none() {
        assert_eq!(empty_to_none(None), None);
        assert_eq!(empty_to_none(Some(String::new())), None);
        assert_eq!(
            empty_to_none(Some("hello".to_string())),
            Some("hello".to_string())
        );
    }
}
