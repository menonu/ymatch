use crate::common::*;

#[sqlx::test]
async fn test_messages_empty_list(pool: PgPool) {
    // Create two users and a match
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "msg-user-1"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u1: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u1_id = u1["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/guest")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"uuid": "msg-user-2"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    let u2: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let u2_id = u2["id"].as_i64().unwrap();

    // Insert match directly. ADR 0001: matches carry (event_id, group_name).
    let event_row: (i32,) = sqlx::query_as(
        "INSERT INTO events (name, creator_id) VALUES ('Match Msg Event', $1) RETURNING id",
    )
    .bind(u1_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();
    let match_row = sqlx::query(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
         VALUES ($1, $2, 'PENDING', $3, 'MsgGroup') RETURNING id",
    )
    .bind(u1_id as i32)
    .bind(u2_id as i32)
    .bind(event_row.0)
    .fetch_one(&pool)
    .await
    .unwrap();
    let match_id: i32 = sqlx::Row::get(&match_row, "id");

    // Send a message
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/messages", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"matchId": {}, "senderId": {}, "content": "Hello!"}}"#,
                    match_id, u1_id
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // List messages
    let app = backend::routes::create_router(pool, test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .uri(&format!("/api/v1/matches/{}/messages", match_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let messages: Vec<serde_json::Value> =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["content"].as_str().unwrap(), "Hello!");
}

#[sqlx::test]
async fn test_notification_counts_values(pool: PgPool) {
    // Set up: 2 users, 1 event, 2 merch items ("Card A", "Card B").
    // We'll create three matches in different states and verify the
    // counts endpoint returns the correct values for each side.
    let (u1, event_id) =
        create_test_user_and_event(pool.clone(), "notif-user-1", "Notif Event").await;
    let (u2, _) = create_test_user_and_event(pool.clone(), "notif-user-2", "Notif Event 2").await;

    // Create merch for each user
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Card A", "groupName": "cards", "creatorId": {}}}"#,
                    u1
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let m_a: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let m_a_id = m_a["id"].as_i64().unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/events/{}/merch", event_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"name": "Card B", "groupName": "cards", "creatorId": {}}}"#,
                    u2
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    let m_b: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    let m_b_id = m_b["id"].as_i64().unwrap();

    // Each user puts the other's card as WANT and their own as TRADE
    for (user_id, merch_id) in [(u1, m_b_id), (u2, m_a_id)] {
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let _ = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "merchId": {}, "status": "WANT", "quantity": 1}}"#,
                        user_id, merch_id
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        let app = backend::routes::create_router(pool.clone(), test_storage());
        let _ = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/user/inventory")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"userId": {}, "merchId": {}, "status": "TRADE", "quantity": 1}}"#,
                        user_id,
                        if user_id == u1 { m_a_id } else { m_b_id }
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
    }

    // Insert match directly (the matching algorithm is out of scope for
    // integration tests; it runs in a background task). ADR 0001: scope the
    // match to the "cards" group of the merch above.
    let match_id: i32 = sqlx::query_scalar(
        "INSERT INTO matches (user1_id, user2_id, status, event_id, group_name)
         VALUES ($1, $2, 'PENDING', $3, 'cards') RETURNING id",
    )
    .bind(u1)
    .bind(u2)
    .bind(event_id as i32)
    .fetch_one(&pool)
    .await
    .unwrap();

    // ---- Query counts: 1 PENDING match exists, 0 messages ----
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json_i64(&body, "pendingMatches"), 1);
    assert_eq!(json_i64(&body, "offersIn"), 0);
    assert_eq!(json_i64(&body, "accepted"), 0);
    assert_eq!(json_i64(&body, "unreadMessages"), 0);
    assert_eq!(json_i64(&body, "total"), 1);

    // User2 should also see pending=1 (they are a participant)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json_i64(&body, "pendingMatches"), 1);

    // ---- Transition to OFFERED via u1 (balanced: give m_a, receive m_b);
    //      send a message from u2 (unread for u1) ----
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/offer", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"userId": {}, "items": [{{"merchId": {}, "giverUserId": {}, "quantity": 1}}, {{"merchId": {}, "giverUserId": {}, "quantity": 1}}]}}"#,
                    u1, m_a_id, u1, m_b_id, u2
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // u2 sends a message (unread for u1)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/messages", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"matchId": {}, "senderId": {}, "content": "hi", "messageType": "TEXT"}}"#,
                    match_id, u2
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Query counts for u1 (the offerer): pending=0, offers_in=0 (u1 is the
    // offerer — they don't see "offers in" for their own offers),
    // unread=1 (u2 just sent a message that u1 hasn't read yet)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json_i64(&body, "pendingMatches"), 0);
    assert_eq!(json_i64(&body, "offersIn"), 0);
    assert_eq!(json_i64(&body, "accepted"), 0);
    assert_eq!(json_i64(&body, "unreadMessages"), 1);
    assert_eq!(json_i64(&body, "total"), 1);

    // Query counts for u2 (the non-offerer): pending=0, offers_in=1 (u2 sees
    // u1's offer as an incoming offer), unread=0 (u2 sent the message; doesn't
    // count as unread for themselves)
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json_i64(&body, "pendingMatches"), 0);
    assert_eq!(json_i64(&body, "offersIn"), 1);
    assert_eq!(json_i64(&body, "accepted"), 0);
    assert_eq!(json_i64(&body, "unreadMessages"), 0);
    assert_eq!(json_i64(&body, "total"), 1);

    // ---- u1 marks their matches_read_at = NOW; unread should drop to 0 ----
    let _ = sqlx::query("UPDATE users SET matches_read_at = NOW() WHERE id = $1")
        .bind(u1)
        .execute(&pool)
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u1))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json_i64(&body, "unreadMessages"), 0);
    assert_eq!(json_i64(&body, "total"), 0); // all zeros for u1 now

    // ---- Transition OFFERED -> ACCEPTED: counts should change again ----
    // Note: the offer's "offeree" is u2; for ACCEPTED, the user_id in
    // the body is the non-proposer accepting (u2).
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let _ = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&format!("/api/v1/matches/{}/status", match_id))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"status": "ACCEPTED", "userId": {}}}"#,
                    u2
                )))
                .unwrap(),
        )
        .await
        .unwrap();

    let app = backend::routes::create_router(pool.clone(), test_storage());
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&format!("/api/v1/matches/user/{}/counts", u2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body: serde_json::Value =
        serde_json::from_str(&body_to_string(resp.into_body()).await).unwrap();
    assert_eq!(json_i64(&body, "pendingMatches"), 0);
    assert_eq!(json_i64(&body, "offersIn"), 0);
    assert_eq!(json_i64(&body, "accepted"), 1);
    assert_eq!(json_i64(&body, "total"), 1);
}
