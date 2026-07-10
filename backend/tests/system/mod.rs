use crate::common::*;

#[sqlx::test]
async fn test_root_endpoint(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(Request::builder().uri("/").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    assert_eq!(body, "Hello from ymatch Rust Backend!");
}

#[sqlx::test]
async fn test_system_status(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());

    let response = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/system/status")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = body_to_string(response.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert!(json.get("backend_version").is_some());
    assert!(json.get("resources").is_some());
}
