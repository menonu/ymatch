//! Read-model queries for matches (list, items, counts, status snapshot).

use super::{
    MATCH_COLUMNS, MatchRepository, MatchStatusSnapshot, match_from_row,
    match_status_snapshot_from_row,
};
use crate::error::AppError;
use crate::generated::ymatch::{MatchItem, NotificationCounts, TradeMatch, User};
use sqlx::Row;
use std::collections::HashMap;

impl MatchRepository {
    // ---- Read methods (use the pool directly) ----

    /// List all matches in the system (admin).
    pub async fn list_all(&self) -> Result<Vec<TradeMatch>, AppError> {
        let sql = format!(
            "SELECT {} FROM matches ORDER BY created_at DESC",
            MATCH_COLUMNS
        );
        let rows = sqlx::query(&sql).fetch_all(&self.pool).await?;
        Ok(rows.iter().map(match_from_row).collect())
    }

    /// List matches for a user with all related data pre-loaded. This is
    /// the N+1 fix — see the module-level docs.
    pub async fn list_for_user(&self, user_id: i32) -> Result<Vec<TradeMatch>, AppError> {
        // Query 1 of 4: matches joined to the "other user" (the participant
        // who is not the requesting user). The CASE picks u.id and
        // u.username without a subquery — single round trip.
        // ADR 0001 / #348: a match is scoped to one (event_id, group_name)
        // (both NOT NULL on `matches` — migration 20260629000000). We read
        // them here so the candidate-item lookup below can be keyed by
        // `(other_id, event_id, group_name)` instead of `other_id` only,
        // which keeps each match's `user_haves`/`user_wants` scoped to its
        // own group (the read-path half of #344; the write path already
        // enforced the invariant).
        // #322: also read the parent event's name so the match card can show
        // `event:group` once. `matches.event_id` is NOT NULL FK → the JOIN
        // always hits a row, and `events.name` is NOT NULL → always Some.
        // #466: LEFT JOIN merchandise_groups for the cosmetic display_name so
        // the card can show a renamed label without mutating group_name.
        let match_sql = r#"SELECT m.id, m.user1_id, m.user2_id, m.status, m.offered_by,
                      m.user1_inventory_applied_at, m.user2_inventory_applied_at,
                      m.created_at, m.event_id, m.group_name, e.name AS event_name,
                      mg.display_name AS group_display_name,
                      m.rematch_count, m.last_terminal_status, m.last_terminal_at,
                      CASE WHEN m.user1_id = $1 THEN m.user2_id ELSE m.user1_id END AS other_id,
                      u.username AS other_username
               FROM matches m
               JOIN users u
                 ON u.id = (CASE WHEN m.user1_id = $1 THEN m.user2_id ELSE m.user1_id END)
               JOIN events e ON e.id = m.event_id
               LEFT JOIN merchandise_groups mg
                 ON mg.event_id = m.event_id AND mg.group_name = m.group_name
               WHERE (m.user1_id = $1 OR m.user2_id = $1)
                 -- ADR 0010: surface CANCELLED under Done; keep REJECTED hidden.
                 AND m.status <> 'REJECTED'
               ORDER BY m.created_at DESC"#;
        let match_rows = sqlx::query(match_sql)
            .bind(user_id)
            .fetch_all(&self.pool)
            .await?;

        if match_rows.is_empty() {
            return Ok(vec![]);
        }

        let match_ids: Vec<i32> = match_rows.iter().map(|r| r.get::<i32, _>("id")).collect();

        // Query 2: haves — the requesting user's TRADE items that
        // match some WANT of any peer.
        //
        // The selected `quantity` is capped to `LEAST(i.quantity, w.quantity)`
        // so the trade-offer dialog never shows (or submits) more units than
        // the receiving side actually wants — issue #294. The server-side
        // `offer` path enforces the same cap independently.
        // ADR 0001 / #348: select the merch row's `event_id` and `group_name`
        // so each candidate item can be keyed by its group below. The match's
        // group comes from the `matches` row; only items whose merch group
        // equals the match's group are attached to that match.
        let have_sql = r#"
            SELECT i.id, i.user_id, i.merch_id, i.status,
                   LEAST(i.quantity, w.quantity) AS quantity,
                   m.name AS merch_name, m.photo_url,
                   m.event_id AS event_id, m.group_name AS group_name,
                   w.user_id AS peer_user_id
            FROM inventory i
            JOIN merchandise m ON m.id = i.merch_id
            JOIN inventory w
              ON w.merch_id = i.merch_id
             AND w.status = 'WANT' AND w.quantity > 0
            WHERE i.user_id = $1
              AND i.status = 'TRADE' AND i.quantity > 0
              AND w.user_id <> $1
              -- ADR 0008: soft-deleted merch is not tradeable; keep it out of
              -- offer candidates even when a PENDING match still exists.
              AND m.is_deleted = false AND m.trade_enabled = true
        "#;
        let have_rows = sqlx::query(have_sql)
            .bind(user_id)
            .fetch_all(&self.pool)
            .await?;

        // Query 3: wants — the mirror of haves, single query. The `quantity`
        // is capped the same way (LEAST of peer's TRADE and requester's WANT).
        //
        // `peer_user_id` is `i.user_id` (the peer who TRADES the item), so
        // `wants_by_peer` is keyed by the peer — matching the `other_id`
        // lookup in the assembly. Previously this keyed by `w.user_id`
        // (the requester), leaving `userWants` always empty (#295).
        let want_sql = r#"
            SELECT i.id, i.user_id, i.merch_id, i.status,
                   LEAST(i.quantity, w.quantity) AS quantity,
                   m.name AS merch_name, m.photo_url,
                   m.event_id AS event_id, m.group_name AS group_name,
                   i.user_id AS peer_user_id
            FROM inventory i
            JOIN merchandise m ON m.id = i.merch_id
            JOIN inventory w
              ON w.merch_id = i.merch_id
             AND w.status = 'WANT' AND w.quantity > 0
            WHERE i.user_id <> $1
              AND i.status = 'TRADE' AND i.quantity > 0
              AND w.user_id = $1
              AND m.is_deleted = false AND m.trade_enabled = true
        "#;
        let want_rows = sqlx::query(want_sql)
            .bind(user_id)
            .fetch_all(&self.pool)
            .await?;

        // Query 4: match_items for the matches we care about, batched.
        // Legs are absolute: each row is "giver_user_id gives merch_id qty".
        let items_sql = r#"
            SELECT mi.id, mi.match_id, mi.merch_id, mi.giver_user_id, mi.quantity,
                   m.name AS merch_name, m.photo_url
            FROM match_items mi
            JOIN merchandise m ON m.id = mi.merch_id
            WHERE mi.match_id = ANY($1)
            ORDER BY mi.giver_user_id, mi.id
        "#;
        let item_rows = sqlx::query(items_sql)
            .bind(&match_ids)
            .fetch_all(&self.pool)
            .await?;

        // ADR 0001 / #348: key candidate items by `(peer, event_id,
        // group_name)` so a match only receives the items that belong to its
        // own group. `merchandise.group_name` is nullable (only non-NULL merch
        // is matchable under ADR 0001, but this read path is independent of
        // the matcher), so decode it as `Option<String>`; a `None` group can
        // never equal a match's NOT NULL group, so such rows are simply never
        // attached to a match — no need to filter them out here.
        let mut haves_by_peer: HashMap<
            (i32, i32, Option<String>),
            Vec<crate::generated::ymatch::InventoryItem>,
        > = HashMap::new();
        for r in &have_rows {
            let peer: i32 = r.get("peer_user_id");
            let event_id: i32 = r.get("event_id");
            let group_name: Option<String> = r.get::<Option<String>, _>("group_name");
            haves_by_peer
                .entry((peer, event_id, group_name.clone()))
                .or_default()
                .push(crate::generated::ymatch::InventoryItem {
                    id: r.get("id"),
                    user_id: r.get("user_id"),
                    merch_id: r.get("merch_id"),
                    status: r.get("status"),
                    quantity: r.get("quantity"),
                    merch_name: Some(r.get("merch_name")),
                    // Decode as Option<String> so NULL photo_url is preserved
                    // as None instead of panicking with UnexpectedNullError
                    // (issue #224). The proto field is `optional string`, so
                    // this matches the wire format.
                    photo_url: r.get::<Option<String>, _>("photo_url"),
                    // #348: populated from the merch row (was hardcoded None).
                    group_name,
                    is_deleted: None,
                });
        }
        let mut wants_by_peer: HashMap<
            (i32, i32, Option<String>),
            Vec<crate::generated::ymatch::InventoryItem>,
        > = HashMap::new();
        for r in &want_rows {
            let peer: i32 = r.get("peer_user_id");
            let event_id: i32 = r.get("event_id");
            let group_name: Option<String> = r.get::<Option<String>, _>("group_name");
            wants_by_peer
                .entry((peer, event_id, group_name.clone()))
                .or_default()
                .push(crate::generated::ymatch::InventoryItem {
                    id: r.get("id"),
                    user_id: r.get("user_id"),
                    merch_id: r.get("merch_id"),
                    status: r.get("status"),
                    quantity: r.get("quantity"),
                    merch_name: Some(r.get("merch_name")),
                    // See #224. Decode as Option<String>.
                    photo_url: r.get::<Option<String>, _>("photo_url"),
                    // #348: populated from the merch row (was hardcoded None).
                    group_name,
                    is_deleted: None,
                });
        }
        let mut items_by_match: HashMap<i32, Vec<MatchItem>> = HashMap::new();
        for r in &item_rows {
            let mid: i32 = r.get("match_id");
            items_by_match.entry(mid).or_default().push(MatchItem {
                id: r.get("id"),
                match_id: mid,
                merch_id: r.get("merch_id"),
                giver_user_id: r.get("giver_user_id"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                // See #224. Decode as Option<String>.
                photo_url: r.get::<Option<String>, _>("photo_url"),
            });
        }

        let mut out: Vec<TradeMatch> = Vec::with_capacity(match_rows.len());
        for row in &match_rows {
            let mut m = match_from_row(row);
            let other_id: i32 = row.get("other_id");
            let other_username: String = row.get("other_username");
            // ADR 0001 / #348: the match's group (NOT NULL on `matches`) picks
            // out only this match's candidate items from the per-group maps.
            let event_id: i32 = row.get("event_id");
            let group_name: String = row.get("group_name");
            // #322: surface the match's `event:group` on the TradeMatch so the
            // card can show it once (both NOT NULL on matches/events).
            // #466: optional cosmetic label; UI falls back to group_name.
            m.group_name = Some(group_name.clone());
            m.event_name = Some(row.get("event_name"));
            m.group_display_name = row
                .get::<Option<String>, _>("group_display_name")
                .filter(|s| !s.is_empty());
            m.other_user = Some(User {
                id: other_id,
                username: other_username,
                uuid: None,
                device_token: None,
                created_at: None,
                role: None,
                is_banned: None,
                ban_reason: None,
                banned_until: None,
            });
            m.user_haves = haves_by_peer
                .get(&(other_id, event_id, Some(group_name.clone())))
                .cloned()
                .unwrap_or_default();
            m.user_wants = wants_by_peer
                .get(&(other_id, event_id, Some(group_name)))
                .cloned()
                .unwrap_or_default();
            m.selected_items = items_by_match.get(&m.id).cloned().unwrap_or_default();
            m.inventory_applied = if m.user1_id == user_id {
                row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("user1_inventory_applied_at")
                    .is_some()
            } else {
                row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("user2_inventory_applied_at")
                    .is_some()
            };
            out.push(m);
        }
        Ok(out)
    }

    /// List `match_items` joined with `merchandise` for the apply endpoint.
    ///
    /// Delegates to [`list_match_items_in_tx`] on the pool. The
    /// transaction-aware variant exists so `change_status`'s accept gate
    /// can read the legs inside the same `FOR UPDATE` transaction it
    /// holds (see [`crate::services::match_lifecycle`]).
    pub async fn list_match_items(&self, match_id: i32) -> Result<Vec<MatchItem>, AppError> {
        self.list_match_items_in_tx(&self.pool, match_id).await
    }

    /// Transaction-aware [`list_match_items`]: same query, run on the
    /// supplied executor so the read participates in the caller's
    /// transaction snapshot (e.g. the accept gate reads legs under the
    /// `FOR UPDATE` lock it already holds).
    pub async fn list_match_items_in_tx<'c, E>(
        &self,
        exec: E,
        match_id: i32,
    ) -> Result<Vec<MatchItem>, AppError>
    where
        E: sqlx::Executor<'c, Database = sqlx::Postgres>,
    {
        let rows = sqlx::query(
            r#"SELECT mi.id, mi.match_id, mi.merch_id, mi.giver_user_id, mi.quantity,
                      m.name AS merch_name, m.photo_url
               FROM match_items mi
               JOIN merchandise m ON m.id = mi.merch_id
               WHERE mi.match_id = $1
               ORDER BY mi.giver_user_id, mi.id"#,
        )
        .bind(match_id)
        .fetch_all(exec)
        .await?;
        Ok(rows
            .iter()
            .map(|r| MatchItem {
                id: r.get("id"),
                match_id: r.get("match_id"),
                merch_id: r.get("merch_id"),
                giver_user_id: r.get("giver_user_id"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                // See #224. Decode as Option<String> directly; no
                // Some(...) wrapper needed (the previous code decoded
                // as String and wrapped in Some, which panicked on
                // NULL photo_url).
                photo_url: r.get::<Option<String>, _>("photo_url"),
            })
            .collect())
    }

    /// Notification counts (pending / offers_in / accepted / unread) for a
    /// user.
    pub async fn notification_counts(&self, user_id: i32) -> Result<NotificationCounts, AppError> {
        let row = sqlx::query(
            r#"SELECT
                   (SELECT COUNT(*) FROM matches
                    WHERE (user1_id = $1 OR user2_id = $1) AND status = 'PENDING') AS pending,
                   (SELECT COUNT(*) FROM matches
                    WHERE (user1_id = $1 OR user2_id = $1)
                      AND status = 'OFFERED' AND offered_by != $1) AS offers_in,
                   (SELECT COUNT(*) FROM matches
                    WHERE (user1_id = $1 OR user2_id = $1) AND status = 'ACCEPTED') AS accepted,
                   (SELECT COUNT(*) FROM messages msg
                    JOIN matches m ON msg.match_id = m.id
                    WHERE (m.user1_id = $1 OR m.user2_id = $1)
                      AND m.status IN ('PENDING', 'OFFERED', 'ACCEPTED')
                      AND msg.sender_id != $1
                      AND msg.created_at > COALESCE(
                        (SELECT matches_read_at FROM users WHERE id = $1),
                        '1970-01-01'::timestamptz
                      )) AS unread
               "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        let pending: i64 = row.get("pending");
        let offers_in: i64 = row.get("offers_in");
        let accepted: i64 = row.get("accepted");
        let unread: i64 = row.get("unread");
        let total = pending + offers_in + accepted + unread;
        Ok(NotificationCounts {
            pending_matches: pending as i32,
            offers_in: offers_in as i32,
            accepted: accepted as i32,
            unread_messages: unread as i32,
            total: total as i32,
        })
    }

    /// Read-only status snapshot (no row lock). Used by chat membership gates
    /// (#491) and other non-mutating checks.
    pub async fn get_status_snapshot(
        &self,
        match_id: i32,
    ) -> Result<Option<MatchStatusSnapshot>, AppError> {
        let row = sqlx::query(
            "SELECT user1_id, user2_id, status, offered_by, event_id, group_name,
                    user1_inventory_applied_at, user2_inventory_applied_at
             FROM matches WHERE id = $1",
        )
        .bind(match_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(match_status_snapshot_from_row))
    }
}
