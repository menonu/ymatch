use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: i32,
    pub username: String,
    // password_hash should not be serialized to JSON usually, but simpler for now
    #[serde(skip)]
    pub password_hash: Option<String>,
    pub uuid: Option<String>,
    pub device_token: Option<String>,
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Event {
    pub id: i32,
    pub name: String,
    pub creator_id: Option<i32>,
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Merchandise {
    pub id: i32,
    pub event_id: i32,
    pub name: String,
    pub photo_url: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct InventoryItem {
    pub id: i32,
    pub user_id: i32,
    pub merch_id: i32,
    pub status: String, // HAVE, WANT
    pub quantity: i32,
    pub updated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct InventoryItemWithDetails {
    pub id: i32,
    pub user_id: i32,
    pub merch_id: i32,
    pub status: String,
    pub quantity: i32,
    pub merch_name: String,
    pub photo_url: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Match {
    pub id: i32,
    pub user1_id: i32,
    pub user2_id: i32,
    pub status: String,
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Message {
    pub id: i32,
    pub match_id: i32,
    pub sender_id: i32,
    pub content: String,
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct GuestLoginRequest {
    pub uuid: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateUserRequest {
    pub username: String,
    pub password: String, // In real app, hash this!
    pub device_token: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateEventRequest {
    pub name: String,
    pub creator_id: i32, // Simplified: client sends ID. Ideally auth token claims.
}

#[derive(Debug, Deserialize)]
pub struct CreateMerchRequest {
    pub name: String,
    pub photo_url: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateInventoryRequest {
    pub user_id: i32, // Simplified
    pub merch_id: i32,
    pub status: String,
    pub quantity: i32,
}
