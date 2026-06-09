//! Central application error type.
//!
//! All HTTP handlers return `Result<T, AppError>`. The [`IntoResponse`]
//! implementation maps each variant to a stable HTTP status code and a
//! human-readable body. The [`From<sqlx::Error>`] impl lets `?` work
//! transparently inside repository and service code.
//!
//! Phase 1 of #163 replaces 71 ad-hoc `.map_err(|e| (StatusCode,
//! INTERNAL_SERVER_ERROR, e.to_string()))?` sites with this single type.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
};
use std::fmt;

/// All errors that handlers in this crate can return to the client.
#[derive(Debug, PartialEq, Eq)]
pub enum AppError {
    /// 400 — the request payload was syntactically valid but semantically wrong
    /// (missing required field, bad enum value, etc.).
    BadRequest(String),

    /// 401 — the request did not authenticate.
    Unauthorized(String),

    /// 403 — the request authenticated but the actor is not allowed.
    Forbidden(String),

    /// 404 — the addressed resource does not exist.
    NotFound(String),

    /// 409 — the request conflicts with current state (e.g. duplicate, applied
    /// twice, banned user).
    Conflict(String),

    /// 500 — an unexpected internal failure. The wrapped string is logged but
    /// not exposed to the client verbatim in the future; today it is forwarded
    /// for backward compatibility with the old `(StatusCode, String)` shape.
    Internal(String),
}

impl AppError {
    pub fn bad_request(msg: impl Into<String>) -> Self {
        Self::BadRequest(msg.into())
    }
    pub fn unauthorized(msg: impl Into<String>) -> Self {
        Self::Unauthorized(msg.into())
    }
    pub fn forbidden(msg: impl Into<String>) -> Self {
        Self::Forbidden(msg.into())
    }
    pub fn not_found(msg: impl Into<String>) -> Self {
        Self::NotFound(msg.into())
    }
    pub fn conflict(msg: impl Into<String>) -> Self {
        Self::Conflict(msg.into())
    }
    pub fn internal(msg: impl Into<String>) -> Self {
        Self::Internal(msg.into())
    }

    fn status_and_message(&self) -> (StatusCode, String) {
        match self {
            Self::BadRequest(m) => (StatusCode::BAD_REQUEST, m.clone()),
            Self::Unauthorized(m) => (StatusCode::UNAUTHORIZED, m.clone()),
            Self::Forbidden(m) => (StatusCode::FORBIDDEN, m.clone()),
            Self::NotFound(m) => (StatusCode::NOT_FOUND, m.clone()),
            Self::Conflict(m) => (StatusCode::CONFLICT, m.clone()),
            Self::Internal(m) => (StatusCode::INTERNAL_SERVER_ERROR, m.clone()),
        }
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let (status, msg) = self.status_and_message();
        write!(f, "{}: {}", status, msg)
    }
}

impl std::error::Error for AppError {}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = self.status_and_message();
        if status == StatusCode::INTERNAL_SERVER_ERROR {
            tracing::error!(error = %message, "internal error");
        }
        (status, message).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        match e {
            sqlx::Error::RowNotFound => Self::not_found("Resource not found"),
            other => Self::internal(other.to_string()),
        }
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        Self::bad_request(format!("Invalid JSON: {}", e))
    }
}

impl From<crate::storage::StorageError> for AppError {
    fn from(e: crate::storage::StorageError) -> Self {
        Self::internal(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bad_request_maps_to_400() {
        let err = AppError::bad_request("missing field");
        let (status, msg) = err.status_and_message();
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(msg, "missing field");
    }

    #[test]
    fn forbidden_maps_to_403() {
        let err = AppError::forbidden("not your merch");
        let (status, _) = err.status_and_message();
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[test]
    fn not_found_maps_to_404() {
        let err = AppError::not_found("user");
        let (status, _) = err.status_and_message();
        assert_eq!(status, StatusCode::NOT_FOUND);
    }

    #[test]
    fn conflict_maps_to_409() {
        let err = AppError::conflict("already applied");
        let (status, _) = err.status_and_message();
        assert_eq!(status, StatusCode::CONFLICT);
    }

    #[test]
    fn internal_maps_to_500() {
        let err = AppError::internal("db blew up");
        let (status, msg) = err.status_and_message();
        assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
        assert_eq!(msg, "db blew up");
    }

    #[test]
    fn sqlx_row_not_found_maps_to_404() {
        let err: AppError = sqlx::Error::RowNotFound.into();
        let (status, _) = err.status_and_message();
        assert_eq!(status, StatusCode::NOT_FOUND);
    }

    #[test]
    fn sqlx_other_error_maps_to_500() {
        let err: AppError = sqlx::Error::PoolClosed.into();
        let (status, _) = err.status_and_message();
        assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    }

    #[test]
    fn serde_json_error_maps_to_400() {
        let bad_json = "{not valid";
        let result: Result<serde_json::Value, _> = serde_json::from_str(bad_json);
        let err: AppError = result.unwrap_err().into();
        let (status, _) = err.status_and_message();
        assert_eq!(status, StatusCode::BAD_REQUEST);
    }

    #[test]
    fn display_includes_status_and_message() {
        let err = AppError::forbidden("nope");
        let s = format!("{}", err);
        assert!(s.contains("403"));
        assert!(s.contains("nope"));
    }
}
