mod handlers;
mod matching;
mod generated;

use axum::{
    routing::{get, post},
    Router,
};
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::from_default_env().add_directive("debug".parse().unwrap()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Connect to Database
    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
        .await
        .expect("Failed to connect to Postgres");

    // Run Migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    tracing::info!("Migrations applied successfully!");

    // CORS Layer
    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    // Basic Router
    let app = Router::new()
        .route("/", get(|| async { "Hello from ymatch Rust Backend!" }))
        // Auth
        .route("/api/v1/auth/signup", post(handlers::signup))
        .route("/api/v1/auth/login", post(handlers::login))
        .route("/api/v1/auth/guest", post(handlers::guest_login))
        .route("/api/v1/users", get(handlers::list_users))
        // Events
        .route("/api/v1/events", get(handlers::list_events).post(handlers::create_event))
        .route("/api/v1/events/:id/favorite", post(handlers::toggle_favorite))
        .route("/api/v1/events/:id/merch", get(handlers::list_merch).post(handlers::create_merch))
        .route("/api/v1/events/:id/merch/sort", post(handlers::update_merch_sort_order))
        // Inventory
        .route("/api/v1/user/inventory", post(handlers::update_inventory))
        .route("/api/v1/user/:id/inventory", get(handlers::get_user_inventory))
        // Matches
        .route("/api/v1/matches/trigger", post(handlers::trigger_matching))
        .route("/api/v1/matches/user/:id", get(handlers::list_matches))
        .with_state(pool)
        .layer(cors);

    // Start Server
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
