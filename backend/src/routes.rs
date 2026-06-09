use axum::{
    Router,
    body::Body,
    extract::{FromRef, Request},
    http::StatusCode,
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{delete, get, post, put},
};
use governor::{DefaultKeyedRateLimiter, Quota, RateLimiter};
use sqlx::PgPool;
use std::{net::IpAddr, num::NonZeroU32, sync::Arc, time::Duration};

use crate::handlers;
use crate::repositories::user::{PgUserRepository, UserRepository};
use crate::services::permissions::PermissionPolicy;
use crate::storage::ImageStorage;

type IpLimiter = DefaultKeyedRateLimiter<IpAddr>;

/// Extract real client IP from X-Forwarded-For header (set by Cloud Run / proxies)
/// or fall back to a zeroed address.
fn extract_client_ip(req: &Request<Body>) -> IpAddr {
    if let Some(forwarded_for) = req.headers().get("x-forwarded-for") {
        if let Ok(value) = forwarded_for.to_str() {
            // X-Forwarded-For may contain multiple IPs; the first is the client
            if let Some(first) = value.split(',').next() {
                if let Ok(ip) = first.trim().parse::<IpAddr>() {
                    return ip;
                }
            }
        }
    }
    IpAddr::from([0, 0, 0, 0])
}

async fn rate_limit(req: Request<Body>, next: Next, limiter: Arc<IpLimiter>) -> Response {
    let ip = extract_client_ip(&req);
    if limiter.check_key(&ip).is_err() {
        return (StatusCode::TOO_MANY_REQUESTS, "Too Many Requests").into_response();
    }
    next.run(req).await
}

/// Single state object passed to every handler. Phase 2 of #163 adds the
/// `users` repository and `policy` service; subsequent phases will replace
/// the raw `pool` access in handlers with more `Repository` fields.
#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub storage: Arc<dyn ImageStorage>,
    pub users: Arc<dyn UserRepository>,
    pub policy: Arc<PermissionPolicy>,
}

impl FromRef<AppState> for PgPool {
    fn from_ref(input: &AppState) -> Self {
        input.pool.clone()
    }
}

impl FromRef<AppState> for Arc<dyn ImageStorage> {
    fn from_ref(input: &AppState) -> Self {
        input.storage.clone()
    }
}

impl FromRef<AppState> for Arc<dyn UserRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.users.clone()
    }
}

impl FromRef<AppState> for Arc<PermissionPolicy> {
    fn from_ref(input: &AppState) -> Self {
        input.policy.clone()
    }
}

pub fn create_router(pool: PgPool, storage: Arc<dyn ImageStorage>) -> Router {
    let users: Arc<dyn UserRepository> = Arc::new(PgUserRepository::new(pool.clone()));
    let policy = Arc::new(PermissionPolicy::new(users.clone()));
    let state = AppState {
        pool,
        storage,
        users,
        policy,
    };

    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    // Auth endpoints: strict — 3 req/s per IP, burst 5 (brute-force protection)
    let auth_limiter = Arc::new(RateLimiter::keyed(
        Quota::per_second(NonZeroU32::new(3).unwrap()).allow_burst(NonZeroU32::new(5).unwrap()),
    ));

    // General API endpoints: relaxed — 30 req/s per IP, burst 60
    let api_limiter = Arc::new(RateLimiter::keyed(
        Quota::per_second(NonZeroU32::new(30).unwrap()).allow_burst(NonZeroU32::new(60).unwrap()),
    ));

    // Periodic cleanup to prevent unbounded memory growth
    let auth_limiter_gc = auth_limiter.clone();
    let api_limiter_gc = api_limiter.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(60)).await;
            auth_limiter_gc.retain_recent();
            api_limiter_gc.retain_recent();
        }
    });

    let auth_routes: Router<AppState> = Router::new()
        .route("/api/v1/auth/signup", post(handlers::signup))
        .route("/api/v1/auth/login", post(handlers::login))
        .route("/api/v1/auth/guest", post(handlers::guest_login))
        .layer(middleware::from_fn_with_state(
            auth_limiter.clone(),
            |axum::extract::State(lim): axum::extract::State<Arc<IpLimiter>>,
             req: Request<Body>,
             next: Next| async move { rate_limit(req, next, lim).await },
        ));

    let api_routes: Router<AppState> = Router::new()
        .route("/", get(|| async { "Hello from ymatch Rust Backend!" }))
        .route("/api/v1/users", get(handlers::list_users))
        .route("/api/v1/users/:id", put(handlers::update_username))
        .route(
            "/api/v1/user/:id/favorite_groups",
            get(handlers::list_favorite_groups),
        )
        .route("/api/v1/system/status", get(handlers::get_system_status))
        .route("/api/v1/search", get(handlers::global_search))
        .route(
            "/api/v1/events",
            get(handlers::list_events).post(handlers::create_event),
        )
        .route(
            "/api/v1/events/:id/view",
            post(handlers::register_event_view),
        )
        .route(
            "/api/v1/events/:id/favorite",
            post(handlers::toggle_favorite),
        )
        .route(
            "/api/v1/events/:id/favorite_group",
            post(handlers::toggle_favorite_group),
        )
        .route("/api/v1/events/:id/publish", post(handlers::publish_event))
        .route(
            "/api/v1/events/:id/merch",
            get(handlers::list_merch).post(handlers::create_merch),
        )
        .route(
            "/api/v1/events/:id/merch/sort",
            post(handlers::update_merch_sort_order),
        )
        .route(
            "/api/v1/events/:id/merch/:merch_id/publish",
            post(handlers::publish_merch),
        )
        .route(
            "/api/v1/events/:id/merch/:merch_id",
            put(handlers::update_merch).delete(handlers::delete_merch_by_creator),
        )
        .route("/api/v1/events/:id", put(handlers::update_event))
        .route("/api/v1/user/inventory", post(handlers::update_inventory))
        .route(
            "/api/v1/user/:id/inventory",
            get(handlers::get_user_inventory),
        )
        .route("/api/v1/admin/merch", get(handlers::list_all_merch))
        .route("/api/v1/admin/matches", get(handlers::list_all_matches))
        .route("/api/v1/admin/events/:id", delete(handlers::delete_event))
        .route("/api/v1/admin/merch/:id", delete(handlers::delete_merch))
        .route("/api/v1/admin/matches/:id", delete(handlers::delete_match))
        .route("/api/v1/admin/users/:id", get(handlers::get_user_details))
        .route("/api/v1/admin/users/:id/ban", post(handlers::ban_user))
        .route("/api/v1/admin/users/:id/unban", post(handlers::unban_user))
        .route(
            "/api/v1/admin/users/:id/role",
            post(handlers::update_user_role),
        )
        .route("/api/v1/matches/user/:id", get(handlers::list_matches))
        .route(
            "/api/v1/matches/user/:id/counts",
            get(handlers::match_notification_counts),
        )
        .route("/api/v1/matches/:id/offer", post(handlers::offer_trade))
        .route(
            "/api/v1/matches/:id/status",
            post(handlers::update_match_status),
        )
        .route(
            "/api/v1/matches/:id/apply-inventory",
            post(handlers::apply_trade_inventory),
        )
        .route(
            "/api/v1/matches/:id/messages",
            get(handlers::list_messages).post(handlers::send_message),
        )
        .layer(middleware::from_fn_with_state(
            api_limiter.clone(),
            |axum::extract::State(lim): axum::extract::State<Arc<IpLimiter>>,
             req: Request<Body>,
             next: Next| async move { rate_limit(req, next, lim).await },
        ));

    // Image upload/delete routes (separate state: Arc<dyn ImageStorage>)
    let image_routes = Router::new()
        .route("/api/v1/images/upload", post(handlers::upload_image))
        .route("/api/v1/images/:filename", delete(handlers::delete_image))
        .with_state(state.storage.clone());

    // Serve local uploads directory as static files
    let upload_dir = std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads".to_string());
    let static_service = tower_http::services::ServeDir::new(upload_dir);

    Router::new()
        .merge(auth_routes.with_state(state.clone()))
        .merge(api_routes.with_state(state.clone()))
        .merge(image_routes)
        .nest_service("/uploads", static_service)
        .layer(cors)
}
