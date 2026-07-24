//! Event ownership service.
//!
//! [`EventService`] owns the multi-statement transactions for event creation
//! and creator transfer. Repositories are single-statement; this service is
//! the place that opens `pool.begin()` for event product paths (#497).
//!
//! - **Create** (ADR 0004 §5): insert the event row and assign
//!   `event/creator` in one transaction so the creator can never end up with
//!   a persisted event they cannot edit/publish.
//! - **Transfer** (#432 / #445): under `SELECT … FOR UPDATE`, update
//!   `events.creator_id` and swap the event-scoped creator role so concurrent
//!   transfers cannot leave two live `event/creator` assignments.

use crate::error::AppError;
use crate::generated::ymatch::Event;
use crate::repositories::event::EventRepository;
use crate::repositories::rbac::RbacRepository;
use sqlx::PgPool;
use std::sync::Arc;

/// Service for event create and creator-transfer transactions.
#[derive(Clone)]
pub struct EventService {
    pool: PgPool,
    events: Arc<EventRepository>,
    rbac: Arc<RbacRepository>,
}

impl EventService {
    pub fn new(pool: PgPool, events: Arc<EventRepository>, rbac: Arc<RbacRepository>) -> Self {
        Self { pool, events, rbac }
    }

    /// Create an event and assign the `event/creator` role atomically.
    ///
    /// Callers are responsible for authorization (`event.create` global) and
    /// verifying the creator is an active user before calling this method.
    pub async fn create(
        &self,
        name: &str,
        creator_id: i32,
        status: Option<&str>,
    ) -> Result<Event, AppError> {
        let mut tx = self.pool.begin().await?;
        let event = self
            .events
            .create(&mut *tx, name, creator_id, status)
            .await?;
        self.rbac
            .assign_event_creator(&mut tx, creator_id, event.id)
            .await?;
        tx.commit().await?;
        Ok(event)
    }

    /// Transfer event ownership: set `events.creator_id` and swap the
    /// event-scoped `creator` role under a row lock.
    ///
    /// When `assert_previous` is `Some(uid)`, the locked creator must equal
    /// `uid` or the call fails with Forbidden (self-service path). When
    /// `None`, any previous creator is accepted (admin path).
    ///
    /// Callers should pre-check event existence, target-user validity, and
    /// authorization; this method re-validates the locked previous creator
    /// so concurrent transfers stay correct (#445).
    pub async fn transfer_creator(
        &self,
        event_id: i32,
        new_creator_id: i32,
        assert_previous: Option<i32>,
    ) -> Result<(), AppError> {
        let mut tx = self.pool.begin().await?;
        let locked_previous = self
            .events
            .lock_creator_for_update(&mut *tx, event_id)
            .await?
            .ok_or_else(|| AppError::not_found("Event not found"))?;

        if let Some(expected) = assert_previous
            && locked_previous != Some(expected)
        {
            return Err(AppError::forbidden(
                "Only the event creator can transfer ownership",
            ));
        }

        if locked_previous == Some(new_creator_id) {
            return Err(AppError::bad_request("User is already the event creator"));
        }

        let updated = self
            .events
            .set_creator(&mut *tx, event_id, new_creator_id)
            .await?;
        if !updated {
            return Err(AppError::not_found("Event not found"));
        }
        self.rbac
            .transfer_event_creator_role(&mut tx, event_id, locked_previous, new_creator_id)
            .await?;
        tx.commit().await?;
        Ok(())
    }
}
