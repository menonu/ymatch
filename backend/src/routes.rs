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
use crate::repositories::event::EventRepository;

/// Read a `NonZeroU32` rate-limit value from the environment, falling
/// back to `default` when the variable is missing or invalid. Used to
/// make the per-IP rate limiters configurable for load-testing and E2E.
fn env_rate_limit(var: &str, default: u32) -> NonZeroU32 {
    std::env::var(var)
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .and_then(NonZeroU32::new)
        .unwrap_or_else(|| NonZeroU32::new(default).unwrap())
}
use crate::repositories::event_favorites::EventFavoritesRepository;
use crate::repositories::event_views::EventViewsRepository;
use crate::repositories::group::MerchandiseGroupRepository;
use crate::repositories::group_favorites::GroupFavoritesRepository;
use crate::repositories::inventory::InventoryRepository;
use crate::repositories::match_::MatchRepository;
use crate::repositories::merch::MerchandiseRepository;
use crate::repositories::message::MessageRepository;
use crate::repositories::rbac::RbacRepository;
use crate::repositories::user::UserRepository;
use crate::services::event::EventService;
use crate::services::group::GroupService;
use crate::services::match_lifecycle::MatchLifecycleService;
use crate::services::permissions::PermissionPolicy;
use crate::services::rbac::RbacService;
use crate::storage::ImageStorage;

type IpLimiter = DefaultKeyedRateLimiter<IpAddr>;

/// Extract real client IP from X-Forwarded-For header (set by Cloud Run / proxies)
/// or fall back to a zeroed address.
fn extract_client_ip(req: &Request<Body>) -> IpAddr {
    if let Some(forwarded_for) = req.headers().get("x-forwarded-for")
        && let Ok(value) = forwarded_for.to_str()
        && let Some(first) = value.split(',').next()
        && let Ok(ip) = first.trim().parse::<IpAddr>()
    {
        // X-Forwarded-For may contain multiple IPs; the first is the client
        return ip;
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
    pub users: Arc<UserRepository>,
    pub merch: Arc<MerchandiseRepository>,
    pub groups: Arc<MerchandiseGroupRepository>,
    pub matches: Arc<MatchRepository>,
    pub inventory: Arc<InventoryRepository>,
    pub messages: Arc<MessageRepository>,
    pub events: Arc<EventRepository>,
    pub event_favorites: Arc<EventFavoritesRepository>,
    pub event_views: Arc<EventViewsRepository>,
    pub group_favorites: Arc<GroupFavoritesRepository>,
    pub policy: Arc<PermissionPolicy>,
    pub match_lifecycle: Arc<MatchLifecycleService>,
    pub event_service: Arc<EventService>,
    pub group_service: Arc<GroupService>,
    pub rbac: Arc<RbacRepository>,
    pub rbac_service: Arc<RbacService>,
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

impl FromRef<AppState> for Arc<UserRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.users.clone()
    }
}

impl FromRef<AppState> for Arc<MerchandiseRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.merch.clone()
    }
}

impl FromRef<AppState> for Arc<MerchandiseGroupRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.groups.clone()
    }
}

impl FromRef<AppState> for Arc<PermissionPolicy> {
    fn from_ref(input: &AppState) -> Self {
        input.policy.clone()
    }
}

impl FromRef<AppState> for Arc<MatchRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.matches.clone()
    }
}

impl FromRef<AppState> for Arc<InventoryRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.inventory.clone()
    }
}

impl FromRef<AppState> for Arc<MessageRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.messages.clone()
    }
}

impl FromRef<AppState> for Arc<MatchLifecycleService> {
    fn from_ref(input: &AppState) -> Self {
        input.match_lifecycle.clone()
    }
}

impl FromRef<AppState> for Arc<EventService> {
    fn from_ref(input: &AppState) -> Self {
        input.event_service.clone()
    }
}

impl FromRef<AppState> for Arc<GroupService> {
    fn from_ref(input: &AppState) -> Self {
        input.group_service.clone()
    }
}

impl FromRef<AppState> for Arc<EventRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.events.clone()
    }
}

impl FromRef<AppState> for Arc<EventFavoritesRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.event_favorites.clone()
    }
}

impl FromRef<AppState> for Arc<EventViewsRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.event_views.clone()
    }
}

impl FromRef<AppState> for Arc<GroupFavoritesRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.group_favorites.clone()
    }
}

impl FromRef<AppState> for Arc<RbacRepository> {
    fn from_ref(input: &AppState) -> Self {
        input.rbac.clone()
    }
}

impl FromRef<AppState> for Arc<RbacService> {
    fn from_ref(input: &AppState) -> Self {
        input.rbac_service.clone()
    }
}

pub fn create_router(pool: PgPool, storage: Arc<dyn ImageStorage>) -> Router {
    let users: Arc<UserRepository> = Arc::new(UserRepository::new(pool.clone()));
    let policy = Arc::new(PermissionPolicy::new(users.clone()));
    let merch: Arc<MerchandiseRepository> = Arc::new(MerchandiseRepository::new(pool.clone()));
    let groups: Arc<MerchandiseGroupRepository> =
        Arc::new(MerchandiseGroupRepository::new(pool.clone()));
    let matches: Arc<MatchRepository> = Arc::new(MatchRepository::new(pool.clone()));
    let inventory: Arc<InventoryRepository> = Arc::new(InventoryRepository::new(pool.clone()));
    let messages: Arc<MessageRepository> = Arc::new(MessageRepository::new(pool.clone()));
    let events: Arc<EventRepository> = Arc::new(EventRepository::new(pool.clone()));
    let event_favorites: Arc<EventFavoritesRepository> =
        Arc::new(EventFavoritesRepository::new(pool.clone()));
    let event_views: Arc<EventViewsRepository> = Arc::new(EventViewsRepository::new(pool.clone()));
    let group_favorites: Arc<GroupFavoritesRepository> =
        Arc::new(GroupFavoritesRepository::new(pool.clone()));
    let match_lifecycle = Arc::new(MatchLifecycleService::new(
        pool.clone(),
        matches.clone(),
        inventory.clone(),
    ));
    let rbac: Arc<RbacRepository> = Arc::new(RbacRepository::new(pool.clone()));
    // The PermissionCatalog is loaded lazily on the first authorization
    // check (RbacService holds a OnceCell) rather than awaited here, so
    // `create_router` can stay synchronous — it is called from ~150 sync
    // call sites in the integration tests. A misconfigured (unseeded) DB
    // surfaces as a 500 on the first check instead of at startup.
    let rbac_service = Arc::new(RbacService::new(rbac.clone(), pool.clone()));
    let event_service = Arc::new(EventService::new(
        pool.clone(),
        events.clone(),
        rbac.clone(),
    ));
    let group_service = Arc::new(GroupService::new(
        pool.clone(),
        groups.clone(),
        rbac.clone(),
    ));
    let state = AppState {
        pool,
        storage,
        users,
        merch,
        groups,
        matches,
        inventory,
        messages,
        events,
        event_favorites,
        event_views,
        group_favorites,
        policy,
        match_lifecycle,
        event_service,
        group_service,
        rbac,
        rbac_service,
    };

    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    // Auth endpoints: strict — 3 req/s per IP, burst 5 (brute-force protection).
    // Overridable via env vars so E2E tests don't trip the limiter.
    let auth_limiter = Arc::new(RateLimiter::keyed(
        Quota::per_second(env_rate_limit("RATE_LIMIT_AUTH_PER_SECOND", 3))
            .allow_burst(env_rate_limit("RATE_LIMIT_AUTH_BURST", 5)),
    ));

    // General API endpoints: relaxed — 30 req/s per IP, burst 60.
    // Overridable via env vars so E2E tests don't trip the limiter.
    let api_limiter = Arc::new(RateLimiter::keyed(
        Quota::per_second(env_rate_limit("RATE_LIMIT_API_PER_SECOND", 30))
            .allow_burst(env_rate_limit("RATE_LIMIT_API_BURST", 60)),
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
            "/api/v1/events/:id/members",
            get(handlers::list_event_members),
        )
        .route(
            "/api/v1/events/:id/my-role",
            get(handlers::get_my_event_role),
        )
        // #442: self-service event creator transfer (current creator only).
        .route(
            "/api/v1/events/:id/creator",
            put(handlers::self_transfer_event_creator),
        )
        .route(
            "/api/v1/events/:id/members/:target_id",
            post(handlers::assign_event_member).delete(handlers::revoke_event_member),
        )
        .route(
            "/api/v1/events/:id/merch",
            get(handlers::list_merch).post(handlers::create_merch),
        )
        .route(
            "/api/v1/events/:id/groups",
            get(handlers::list_event_groups).post(handlers::create_event_group),
        )
        .route(
            "/api/v1/events/:id/groups/:group_name",
            put(handlers::update_event_group),
        )
        // #443: group-scoped self-service members + my-role + creator transfer.
        .route(
            "/api/v1/events/:id/groups/:group_name/members",
            get(handlers::list_group_members),
        )
        .route(
            "/api/v1/events/:id/groups/:group_name/my-role",
            get(handlers::get_my_group_role),
        )
        .route(
            "/api/v1/events/:id/groups/:group_name/creator",
            put(handlers::self_transfer_group_creator),
        )
        .route(
            "/api/v1/events/:id/groups/:group_name/members/:target_id",
            post(handlers::assign_group_member).delete(handlers::revoke_group_member),
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
        .route("/api/v1/admin/groups", get(handlers::list_groups))
        .route(
            "/api/v1/admin/events/:id/groups/:group_name",
            delete(handlers::delete_group),
        )
        // #432: transfer group ownership (created_by).
        .route(
            "/api/v1/admin/events/:id/groups/:group_name/creator",
            put(handlers::transfer_group_creator),
        )
        .route("/api/v1/admin/matches", get(handlers::list_all_matches))
        .route("/api/v1/admin/events/:id", delete(handlers::delete_event))
        // #432: transfer event ownership (creator_id + event/creator role).
        .route(
            "/api/v1/admin/events/:id/creator",
            put(handlers::transfer_event_creator),
        )
        // #432: admin-path event member management (moderator + admin).
        .route(
            "/api/v1/admin/events/:id/members",
            get(handlers::admin_list_event_members),
        )
        .route(
            "/api/v1/admin/events/:id/members/:target_id",
            post(handlers::admin_assign_event_member).delete(handlers::admin_revoke_event_member),
        )
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
        // #491: images share AppState so upload/delete can require an active user.
        .route("/api/v1/images/upload", post(handlers::upload_image))
        .route("/api/v1/images/:filename", delete(handlers::delete_image))
        .layer(middleware::from_fn_with_state(
            api_limiter.clone(),
            |axum::extract::State(lim): axum::extract::State<Arc<IpLimiter>>,
             req: Request<Body>,
             next: Next| async move { rate_limit(req, next, lim).await },
        ));

    // Serve local uploads directory as static files
    let upload_dir = std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads".to_string());
    let static_service = tower_http::services::ServeDir::new(upload_dir);

    Router::new()
        .merge(auth_routes.with_state(state.clone()))
        .merge(api_routes.with_state(state.clone()))
        .nest_service("/uploads", static_service)
        .layer(cors)
}

#[cfg(test)]
mod tests {
    use super::*;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    // --- env_rate_limit ---

    #[test]
    fn env_rate_limit_falls_back_to_default_when_unset() {
        // Read-only: a unique, never-set var name. Edition 2024 makes
        // `std::env::set_var` unsafe and racy under parallel `cargo test`,
        // so this only exercises the unset → default path (no mutation).
        assert_eq!(
            env_rate_limit("TEST_RL_UNSET_185_A", 42),
            NonZeroU32::new(42).unwrap()
        );
    }

    // --- extract_client_ip ---

    /// Build a GET request with an optional `x-forwarded-for` header.
    fn req_with_xff(header: Option<&str>) -> Request<Body> {
        let mut builder = Request::builder().method("GET").uri("/");
        if let Some(value) = header {
            builder = builder.header("x-forwarded-for", value);
        }
        builder.body(Body::empty()).unwrap()
    }

    #[test]
    fn extract_client_ip_reads_single_xff() {
        assert_eq!(
            extract_client_ip(&req_with_xff(Some("1.2.3.4"))),
            "1.2.3.4".parse::<IpAddr>().unwrap(),
        );
    }

    #[test]
    fn extract_client_ip_takes_first_of_many_xff() {
        assert_eq!(
            extract_client_ip(&req_with_xff(Some("1.2.3.4, 5.6.7.8"))),
            "1.2.3.4".parse::<IpAddr>().unwrap(),
        );
    }

    #[test]
    fn extract_client_ip_missing_header_falls_back_to_zero() {
        assert_eq!(
            extract_client_ip(&req_with_xff(None)),
            IpAddr::from([0, 0, 0, 0]),
        );
    }

    #[test]
    fn extract_client_ip_invalid_ip_falls_back_to_zero() {
        assert_eq!(
            extract_client_ip(&req_with_xff(Some("not-an-ip"))),
            IpAddr::from([0, 0, 0, 0]),
        );
    }

    // --- rate_limit middleware (via a tiny standalone router + oneshot) ---

    /// Build a router with a 1 req/s, burst-2 limiter wired through
    /// `rate_limit`. No `AppState`, pool, or storage — the rate-limit layer
    /// short-circuits before any handler runs.
    fn rate_limited_app() -> Router {
        let limiter: Arc<IpLimiter> = Arc::new(RateLimiter::keyed(
            Quota::per_second(NonZeroU32::new(1).unwrap()).allow_burst(NonZeroU32::new(2).unwrap()),
        ));
        Router::new()
            .route("/", get(|| async { "ok" }))
            .layer(middleware::from_fn_with_state(
                limiter,
                |axum::extract::State(lim): axum::extract::State<Arc<IpLimiter>>,
                 req: Request<Body>,
                 next: Next| async move { rate_limit(req, next, lim).await },
            ))
    }

    async fn body_string(response: Response) -> String {
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        String::from_utf8(bytes.to_vec()).unwrap()
    }

    #[tokio::test]
    async fn rate_limit_passes_when_under_quota() {
        let app = rate_limited_app();
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        assert_eq!(body_string(res).await, "ok");
    }

    #[tokio::test]
    async fn rate_limit_returns_429_when_burst_exceeded() {
        let app = rate_limited_app();
        // Same client IP (no x-forwarded-for → 0.0.0.0) for all requests.
        // Burst is 2, so the first two consume the budget and the third is
        // rejected. The three in-process `oneshot`s complete in well under
        // the 1s refill window, so the third is deterministically 429 (a
        // sub-millisecond refill is far less than one whole token).
        let req = || {
            Request::builder()
                .method("GET")
                .uri("/")
                .body(Body::empty())
                .unwrap()
        };
        let first = app.clone().oneshot(req()).await.unwrap();
        assert_eq!(first.status(), StatusCode::OK);

        let second = app.clone().oneshot(req()).await.unwrap();
        assert_eq!(second.status(), StatusCode::OK);

        let third = app.oneshot(req()).await.unwrap();
        assert_eq!(third.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_eq!(body_string(third).await, "Too Many Requests");
    }

    #[tokio::test]
    async fn rate_limit_isolates_buckets_per_ip() {
        let app = rate_limited_app();
        // Two distinct client IPs each get their own burst budget, so both
        // requests pass (a single IP would only be limited after its own 2).
        let a = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/")
                    .header("x-forwarded-for", "10.0.0.1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let b = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/")
                    .header("x-forwarded-for", "10.0.0.2")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(a.status(), StatusCode::OK);
        assert_eq!(b.status(), StatusCode::OK);
    }
}
