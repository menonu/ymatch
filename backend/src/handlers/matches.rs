use crate::generated::ymatch::*;
use axum::{extract::Path, extract::State, http::StatusCode, Json};
use sqlx::{PgPool, Row};

pub async fn list_all_matches(
    State(pool): State<PgPool>,
) -> Result<Json<Vec<TradeMatch>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, user1_id, user2_id, status, offered_by, user1_inventory_applied_at, user2_inventory_applied_at, created_at FROM matches ORDER BY created_at DESC",
    )
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut matches = Vec::new();
    for row in rows {
        matches.push(TradeMatch {
            id: row.get("id"),
            user1_id: row.get("user1_id"),
            user2_id: row.get("user2_id"),
            status: row.get("status"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            offered_by: row.get("offered_by"),
            inventory_applied: false,
            other_user: None,
            user_haves: vec![],
            user_wants: vec![],
            selected_items: vec![],
        });
    }

    Ok(Json(matches))
}

pub async fn list_matches(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> Result<Json<Vec<TradeMatch>>, (StatusCode, String)> {
    let rows = sqlx::query(
        "SELECT id, user1_id, user2_id, status, offered_by, user1_inventory_applied_at, user2_inventory_applied_at, created_at FROM matches WHERE (user1_id = $1 OR user2_id = $1) AND status != 'REJECTED' ORDER BY created_at DESC"
    )
    .bind(user_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut matches = Vec::new();
    for row in rows {
        let match_id: i32 = row.get("id");
        let u1: i32 = row.get("user1_id");
        let u2: i32 = row.get("user2_id");
        let other_user_id = if u1 == user_id { u2 } else { u1 };

        let other_user_row = sqlx::query("SELECT id, username FROM users WHERE id = $1")
            .bind(other_user_id)
            .fetch_one(&pool)
            .await
            .ok();

        let other_user = other_user_row.map(|r| User {
            id: r.get("id"),
            username: r.get("username"),
            uuid: None,
            device_token: None,
            created_at: None,
            role: None,
            is_banned: None,
            ban_reason: None,
            banned_until: None,
        });

        // Potential items user can give (user's TRADE that other WANTs)
        let haves_rows = sqlx::query(
            r#"
            SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.name as merch_name, m.photo_url
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $1 AND i.status = 'TRADE' AND i.quantity > 0
            AND EXISTS (
                SELECT 1 FROM inventory w WHERE w.user_id = $2 AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0
            )
            "#
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let user_haves: Vec<InventoryItem> = haves_rows
            .into_iter()
            .map(|r| InventoryItem {
                id: r.get("id"),
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                status: r.get("status"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
                group_name: None,
            })
            .collect();

        // Potential items user receives (other's TRADE that user WANTs)
        let wants_rows = sqlx::query(
            r#"
            SELECT i.id, i.user_id, i.merch_id, i.status, i.quantity, m.name as merch_name, m.photo_url
            FROM inventory i
            JOIN merchandise m ON i.merch_id = m.id
            WHERE i.user_id = $2 AND i.status = 'TRADE' AND i.quantity > 0
            AND EXISTS (
                SELECT 1 FROM inventory w WHERE w.user_id = $1 AND w.merch_id = i.merch_id AND w.status = 'WANT' AND w.quantity > 0
            )
            "#
        )
        .bind(user_id)
        .bind(other_user_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let user_wants: Vec<InventoryItem> = wants_rows
            .into_iter()
            .map(|r| InventoryItem {
                id: r.get("id"),
                user_id: r.get("user_id"),
                merch_id: r.get("merch_id"),
                status: r.get("status"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
                group_name: None,
            })
            .collect();

        // Selected items for OFFERED/ACCEPTED/COMPLETED matches
        let selected_items_rows = sqlx::query(
            r#"
            SELECT mi.id, mi.match_id, mi.merch_id, mi.owner_id, mi.direction, mi.quantity,
                   m.name as merch_name, m.photo_url
            FROM match_items mi
            JOIN merchandise m ON mi.merch_id = m.id
            WHERE mi.match_id = $1
            ORDER BY mi.direction, mi.id
            "#,
        )
        .bind(match_id)
        .fetch_all(&pool)
        .await
        .unwrap_or_default();

        let selected_items: Vec<MatchItem> = selected_items_rows
            .into_iter()
            .map(|r| MatchItem {
                id: r.get("id"),
                match_id: r.get("match_id"),
                merch_id: r.get("merch_id"),
                owner_id: r.get("owner_id"),
                direction: r.get("direction"),
                quantity: r.get("quantity"),
                merch_name: Some(r.get("merch_name")),
                photo_url: r.get("photo_url"),
            })
            .collect();

        matches.push(TradeMatch {
            id: match_id,
            user1_id: u1,
            user2_id: u2,
            status: row.get("status"),
            created_at: row
                .get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at")
                .map(|dt| dt.to_rfc3339()),
            offered_by: row.get("offered_by"),
            inventory_applied: if u1 == user_id {
                row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("user1_inventory_applied_at")
                    .is_some()
            } else {
                row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("user2_inventory_applied_at")
                    .is_some()
            },
            other_user,
            user_haves,
            user_wants,
            selected_items,
        });
    }

    Ok(Json(matches))
}

/// Submit an offer: select items for trade, transition PENDING → OFFERED
pub async fn offer_trade(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<OfferTradeRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Verify match is PENDING and user is part of it
    let match_row =
        sqlx::query("SELECT user1_id, user2_id, status FROM matches WHERE id = $1 FOR UPDATE")
            .bind(match_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let match_row = match_row.ok_or((StatusCode::NOT_FOUND, "Match not found".to_string()))?;
    let status: String = match_row.get("status");
    if status != "PENDING" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Can only offer on PENDING matches".to_string(),
        ));
    }

    let u1: i32 = match_row.get("user1_id");
    let u2: i32 = match_row.get("user2_id");
    if payload.user_id != u1 && payload.user_id != u2 {
        return Err((StatusCode::FORBIDDEN, "Not part of this match".to_string()));
    }

    if payload.items.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Must select at least one item".to_string(),
        ));
    }

    // Insert selected items
    for item in &payload.items {
        sqlx::query(
            "INSERT INTO match_items (match_id, merch_id, owner_id, direction, quantity) VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(match_id)
        .bind(item.merch_id)
        .bind(payload.user_id)
        .bind(&item.direction)
        .bind(item.quantity)
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    // Update match status to OFFERED
    sqlx::query("UPDATE matches SET status = 'OFFERED', offered_by = $1 WHERE id = $2")
        .bind(payload.user_id)
        .bind(match_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

pub async fn update_match_status(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<UpdateMatchStatusRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let valid_statuses = ["ACCEPTED", "REJECTED", "COMPLETED"];
    if !valid_statuses.contains(&payload.status.as_str()) {
        return Err((StatusCode::BAD_REQUEST, "Invalid status".to_string()));
    }

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let match_row = sqlx::query(
        "SELECT user1_id, user2_id, status, offered_by FROM matches WHERE id = $1 FOR UPDATE",
    )
    .bind(match_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let match_row = match_row.ok_or((StatusCode::NOT_FOUND, "Match not found".to_string()))?;
    let current_status: String = match_row.get("status");

    // Validate state transitions
    match (payload.status.as_str(), current_status.as_str()) {
        ("ACCEPTED", status) if status != "OFFERED" => {
            return Err((
                StatusCode::BAD_REQUEST,
                "Can only accept OFFERED matches".to_string(),
            ));
        }
        ("COMPLETED", status) if status != "ACCEPTED" => {
            return Err((
                StatusCode::BAD_REQUEST,
                "Can only complete ACCEPTED matches".to_string(),
            ));
        }
        ("REJECTED", status) if status != "PENDING" && status != "OFFERED" => {
            return Err((
                StatusCode::BAD_REQUEST,
                "Can only reject PENDING or OFFERED matches".to_string(),
            ));
        }
        _ => {}
    }

    sqlx::query("UPDATE matches SET status = $1 WHERE id = $2")
        .bind(&payload.status)
        .bind(match_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // On ACCEPTED: delete other PENDING matches between these users
    if payload.status == "ACCEPTED" {
        let u1: i32 = match_row.get("user1_id");
        let u2: i32 = match_row.get("user2_id");

        sqlx::query("DELETE FROM matches WHERE status = 'PENDING' AND id != $1 AND ((user1_id = $2 AND user2_id = $3) OR (user1_id = $3 AND user2_id = $2))")
            .bind(match_id)
            .bind(u1)
            .bind(u2)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    // On REJECTED: clean up match_items
    if payload.status == "REJECTED" {
        sqlx::query("DELETE FROM match_items WHERE match_id = $1")
            .bind(match_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
    }

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

/// Post-complete: apply inventory changes for the requesting user only
pub async fn apply_trade_inventory(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<ApplyInventoryRequest>,
) -> Result<StatusCode, (StatusCode, String)> {
    let match_row = sqlx::query(
        "SELECT user1_id, user2_id, status, offered_by, user1_inventory_applied_at, user2_inventory_applied_at FROM matches WHERE id = $1",
    )
    .bind(match_id)
    .fetch_optional(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let match_row = match_row.ok_or((StatusCode::NOT_FOUND, "Match not found".to_string()))?;
    let status: String = match_row.get("status");
    if status != "COMPLETED" {
        return Err((
            StatusCode::BAD_REQUEST,
            "Can only apply inventory on COMPLETED matches".to_string(),
        ));
    }

    let u1: i32 = match_row.get("user1_id");
    let u2: i32 = match_row.get("user2_id");
    if payload.user_id != u1 && payload.user_id != u2 {
        return Err((StatusCode::FORBIDDEN, "Not part of this match".to_string()));
    }

    let is_user1 = payload.user_id == u1;
    let already_applied: Option<chrono::DateTime<chrono::Utc>> = if is_user1 {
        match_row.get("user1_inventory_applied_at")
    } else {
        match_row.get("user2_inventory_applied_at")
    };
    if already_applied.is_some() {
        return Err((
            StatusCode::CONFLICT,
            "Inventory already applied for this user".to_string(),
        ));
    }

    let offered_by: Option<i32> = match_row.get("offered_by");
    let offerer = offered_by.unwrap_or(u1);
    let requesting_is_offerer = payload.user_id == offerer;

    let items = sqlx::query(
        "SELECT merch_id, owner_id, direction, quantity FROM match_items WHERE match_id = $1",
    )
    .bind(match_id)
    .fetch_all(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut tx = pool
        .begin()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Only update the requesting user's inventory
    for item in &items {
        let merch_id: i32 = item.get("merch_id");
        let direction: String = item.get("direction");
        let qty: i32 = item.get("quantity");

        // Items stored from offerer's perspective:
        //   GIVE = offerer gives, other receives
        //   RECEIVE = offerer receives, other gives
        if requesting_is_offerer {
            if direction == "GIVE" {
                // Offerer gave this item: decrease offerer's TRADE
                sqlx::query(
                    "UPDATE inventory SET quantity = GREATEST(quantity - $1, 0) WHERE user_id = $2 AND merch_id = $3 AND status = 'TRADE'",
                )
                .bind(qty)
                .bind(payload.user_id)
                .bind(merch_id)
                .execute(&mut *tx)
                .await
                .ok();
            } else if direction == "RECEIVE" {
                // Offerer received this item: increase offerer's HAVE
                sqlx::query(
                    r#"INSERT INTO inventory (user_id, merch_id, status, quantity)
                       VALUES ($1, $2, 'HAVE', $3)
                       ON CONFLICT (user_id, merch_id, status)
                       DO UPDATE SET quantity = inventory.quantity + $3"#,
                )
                .bind(payload.user_id)
                .bind(merch_id)
                .bind(qty)
                .execute(&mut *tx)
                .await
                .ok();
            }
        } else {
            // Requesting user is the other (non-offerer)
            if direction == "GIVE" {
                // Offerer gave → other received: increase other's HAVE
                sqlx::query(
                    r#"INSERT INTO inventory (user_id, merch_id, status, quantity)
                       VALUES ($1, $2, 'HAVE', $3)
                       ON CONFLICT (user_id, merch_id, status)
                       DO UPDATE SET quantity = inventory.quantity + $3"#,
                )
                .bind(payload.user_id)
                .bind(merch_id)
                .bind(qty)
                .execute(&mut *tx)
                .await
                .ok();
            } else if direction == "RECEIVE" {
                // Offerer received → other gave: decrease other's TRADE
                sqlx::query(
                    "UPDATE inventory SET quantity = GREATEST(quantity - $1, 0) WHERE user_id = $2 AND merch_id = $3 AND status = 'TRADE'",
                )
                .bind(qty)
                .bind(payload.user_id)
                .bind(merch_id)
                .execute(&mut *tx)
                .await
                .ok();
            }
        }
    }

    // Mark as applied for this user only
    let applied_col = if is_user1 {
        "user1_inventory_applied_at"
    } else {
        "user2_inventory_applied_at"
    };
    sqlx::query(&format!(
        "UPDATE matches SET {} = NOW() WHERE id = $1",
        applied_col
    ))
    .bind(match_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    tx.commit()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(StatusCode::OK)
}

/// Get notification counts for matches
pub async fn match_notification_counts(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> Result<Json<NotificationCounts>, (StatusCode, String)> {
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM matches WHERE (user1_id = $1 OR user2_id = $1) AND status = 'PENDING'",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let offers_in: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM matches WHERE (user1_id = $1 OR user2_id = $1) AND status = 'OFFERED' AND offered_by != $1",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let accepted: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM matches WHERE (user1_id = $1 OR user2_id = $1) AND status = 'ACCEPTED'",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Unread messages: messages in active matches not sent by this user, created after user's last read
    let unread: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM messages msg
           JOIN matches m ON msg.match_id = m.id
           WHERE (m.user1_id = $1 OR m.user2_id = $1)
             AND m.status IN ('PENDING', 'OFFERED', 'ACCEPTED')
             AND msg.sender_id != $1
             AND msg.created_at > COALESCE(
               (SELECT matches_read_at FROM users WHERE id = $1),
               '1970-01-01'::timestamptz
             )"#,
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let total = pending + offers_in + accepted + unread;

    Ok(Json(NotificationCounts {
        pending_matches: pending as i32,
        offers_in: offers_in as i32,
        accepted: accepted as i32,
        unread_messages: unread as i32,
        total: total as i32,
    }))
}
