use axum::{
    routing::{delete, get, post},
    Router,
};
use sqlx::PgPool;

use crate::handlers;

pub fn create_router(pool: PgPool) -> Router {
    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    Router::new()
        .route("/", get(|| async { "Hello from ymatch Rust Backend!" }))
        // Auth
        .route("/api/v1/auth/signup", post(handlers::signup))
        .route("/api/v1/auth/login", post(handlers::login))
        .route("/api/v1/auth/guest", post(handlers::guest_login))
        .route("/api/v1/users", get(handlers::list_users))
        .route(
            "/api/v1/user/:id/favorite_groups",
            get(handlers::list_favorite_groups),
        )
        // System
        .route("/api/v1/system/status", get(handlers::get_system_status))
        // Search
        .route("/api/v1/search", get(handlers::global_search))
        // Events
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
            delete(handlers::delete_merch_by_creator),
        )
        // Inventory
        .route("/api/v1/user/inventory", post(handlers::update_inventory))
        .route(
            "/api/v1/user/:id/inventory",
            get(handlers::get_user_inventory),
        )
        // Admin
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
        // Matches
        .route("/api/v1/matches/user/:id", get(handlers::list_matches))
        .route(
            "/api/v1/matches/:id/status",
            post(handlers::update_match_status),
        )
        // Messages
        .route(
            "/api/v1/matches/:id/messages",
            get(handlers::list_messages).post(handlers::send_message),
        )
        .with_state(pool)
        .layer(cors)
}
