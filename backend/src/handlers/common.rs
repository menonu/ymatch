//! Shared handler request DTOs used by more than one handler module.
//!
//! Keep types here when both public and admin (or other) routes need the same
//! query/body shape so public handlers do not depend on the admin module (#447).

/// Query wrapper for the ubiquitous `?user_id=` caller identity param.
#[derive(serde::Deserialize)]
pub struct UserIdQuery {
    pub user_id: Option<i32>,
}

/// Body for event/group creator-transfer endpoints (admin #432 and self-service #442).
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferCreatorRequest {
    pub new_creator_id: i32,
}
