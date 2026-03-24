use backend::matching;
use backend::routes;
use backend::storage;

use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("debug".parse().unwrap()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
        .await
        .expect("Failed to connect to Postgres");

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    tracing::info!("Migrations applied successfully!");

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);

    // Build base URL for local storage (used for generating image URLs)
    let base_url = format!("http://0.0.0.0:{}", port);
    let image_storage = storage::create_storage(&base_url).await;
    let storage_type = std::env::var("IMAGE_STORAGE").unwrap_or_else(|_| "local".to_string());
    tracing::info!("Image storage backend: {}", storage_type);

    let app = routes::create_router(pool.clone(), image_storage);

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;

    let matching_pool = pool.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        loop {
            interval.tick().await;
            tracing::info!("Running periodic matching algorithm...");
            match matching::run_matching_algorithm(&matching_pool).await {
                Ok(count) => {
                    if count > 0 {
                        tracing::info!("Created {} new matches automatically.", count);
                    }
                }
                Err(e) => {
                    tracing::error!("Error during automatic matching: {}", e);
                }
            }
        }
    });

    axum::serve(listener, app).await?;

    Ok(())
}
