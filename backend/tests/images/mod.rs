use crate::common::*;

/// Build a minimal but valid `multipart/form-data` body for a single file
/// field. The handler only ever looks at the "file" field; tests that want
/// to exercise other paths pass a different `field_name`.
fn multipart_image_body(
    boundary: &str,
    field_name: &str,
    filename: &str,
    content_type: &str,
    bytes: &[u8],
) -> Vec<u8> {
    let mut body = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!(
            "Content-Disposition: form-data; name=\"{field_name}\"; filename=\"{filename}\"\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {content_type}\r\n\r\n").as_bytes());
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

/// Minimal PNG signature so the storage path is exercised even though
/// the handler does not decode the image.
fn minimal_png_bytes() -> Vec<u8> {
    vec![
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52,
    ]
}

async fn active_user(pool: &PgPool, uuid: &str) -> i64 {
    login_guest(pool, uuid, "img-tok").await
}

fn upload_uri(user_id: i64) -> String {
    format!("/api/v1/images/upload?user_id={user_id}")
}

fn delete_uri(filename: &str, user_id: i64) -> String {
    format!("/api/v1/images/{filename}?user_id={user_id}")
}

#[sqlx::test]
async fn test_upload_image_requires_user_id(pool: PgPool) {
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "NOAUTH";
    let body = multipart_image_body(
        boundary,
        "file",
        "tiny.png",
        "image/png",
        &minimal_png_bytes(),
    );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/images/upload")
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_upload_image_png_succeeds(pool: PgPool) {
    let user_id = active_user(&pool, "img-upload-png").await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "TESTBOUNDARY";
    let body = multipart_image_body(
        boundary,
        "file",
        "tiny.png",
        "image/png",
        &minimal_png_bytes(),
    );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(upload_uri(user_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body_text).unwrap();
    let url = json["url"].as_str().expect("response must include url");
    assert!(
        url.ends_with(".png"),
        "URL should keep the original extension: {url}"
    );
    // LocalFileStorage writes to ./test_uploads/<unique>.png — confirm.
    let filename = url.rsplit('/').next().unwrap();
    let path = std::path::Path::new("./test_uploads").join(filename);
    assert!(
        path.exists(),
        "uploaded file should exist on disk at {path:?}"
    );
    let _ = std::fs::remove_file(&path);
}

#[sqlx::test]
async fn test_upload_image_jpg_succeeds(pool: PgPool) {
    let user_id = active_user(&pool, "img-upload-jpg").await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "JPGBOUNDARY";
    // Real JPG SOI marker so the bytes look like a JPG.
    let bytes = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    let body = multipart_image_body(boundary, "file", "pic.jpg", "image/jpeg", &bytes);

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(upload_uri(user_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body_text).unwrap();
    let url = json["url"].as_str().expect("response must include url");
    assert!(url.ends_with(".jpg"));
    let filename = url.rsplit('/').next().unwrap();
    let path = std::path::Path::new("./test_uploads").join(filename);
    let _ = std::fs::remove_file(&path);
}

#[sqlx::test]
async fn test_upload_image_wrong_content_type_rejected(pool: PgPool) {
    let user_id = active_user(&pool, "img-upload-badtype").await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "TXTBOUNDARY";
    let body = multipart_image_body(boundary, "file", "doc.txt", "text/plain", b"hello world");

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(upload_uri(user_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_upload_image_too_large_rejected(pool: PgPool) {
    let user_id = active_user(&pool, "img-upload-big").await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "BIGBOUNDARY";
    // 1.5 MB to exceed the 1 MiB cap.
    let big = vec![0u8; 1_572_864];
    let body = multipart_image_body(boundary, "file", "huge.png", "image/png", &big);

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(upload_uri(user_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_upload_image_no_file_field_rejected(pool: PgPool) {
    let user_id = active_user(&pool, "img-upload-nofile").await;
    let app = backend::routes::create_router(pool, test_storage());
    let boundary = "NOFILEBOUNDARY";
    // Use a different field name; handler expects "file".
    let body = multipart_image_body(
        boundary,
        "attachment",
        "tiny.png",
        "image/png",
        &minimal_png_bytes(),
    );

    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(upload_uri(user_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}

#[sqlx::test]
async fn test_delete_image_succeeds(pool: PgPool) {
    let user_id = active_user(&pool, "img-delete-ok").await;
    let app = backend::routes::create_router(pool.clone(), test_storage());
    let boundary = "DELBOUNDARY";
    // Upload first.
    let body = multipart_image_body(
        boundary,
        "file",
        "todelete.png",
        "image/png",
        &minimal_png_bytes(),
    );
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(upload_uri(user_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let url = serde_json::from_str::<serde_json::Value>(&body_text).unwrap()["url"]
        .as_str()
        .unwrap()
        .to_string();
    let filename = url.rsplit('/').next().unwrap().to_string();
    let path = std::path::Path::new("./test_uploads").join(&filename);
    assert!(path.exists());

    // Now delete via a fresh router.
    let app2 = backend::routes::create_router(pool, test_storage());
    let resp = app2
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(delete_uri(&filename, user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_text = body_to_string(resp.into_body()).await;
    let json: serde_json::Value = serde_json::from_str(&body_text).unwrap();
    assert_eq!(json["status"], "deleted");
    assert!(!path.exists(), "file should be gone after DELETE");
}

#[sqlx::test]
async fn test_delete_image_nonexistent_is_idempotent(pool: PgPool) {
    let user_id = active_user(&pool, "img-delete-missing").await;
    let app = backend::routes::create_router(pool, test_storage());

    let resp = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(delete_uri("does-not-exist.png", user_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    // LocalFileStorage treats missing files as success (idempotent delete).
    assert_eq!(resp.status(), StatusCode::OK);
}
