//! Merchandise-group ownership service.
//!
//! [`GroupService`] owns the multi-statement transactions for group creation
//! and creator transfer. Repositories are single-statement; this service is
//! the place that opens `pool.begin()` for group product paths (#497).
//!
//! - **Create** (#443 / #491): upsert the group row and assign `group/creator`
//!   for the row's `created_by` in one transaction.
//! - **Transfer** (#432 / #443 / #445): under `SELECT … FOR UPDATE`, update
//!   `merchandise_groups.created_by` and swap the group-scoped creator role so
//!   concurrent transfers cannot leave two live `group/creator` assignments.

use crate::error::AppError;
use crate::generated::ymatch::{CreateGroupRequest, MerchandiseGroup};
use crate::repositories::group::MerchandiseGroupRepository;
use crate::repositories::rbac::RbacRepository;
use sqlx::PgPool;
use std::sync::Arc;

/// Who is initiating a group creator transfer (authorization already done).
///
/// Distinguishes self-service (must still own the row under lock) from admin
/// (may reassign regardless of locked previous creator).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferCaller {
    /// Current group creator self-service path. Locked `created_by` must equal
    /// `expected_creator_id` or the transfer is Forbidden.
    SelfService { expected_creator_id: i32 },
    /// Admin path (`group.creator.transfer`). Any previous creator is accepted.
    Admin,
}

/// Service for group create and creator-transfer transactions.
#[derive(Clone)]
pub struct GroupService {
    pool: PgPool,
    groups: Arc<MerchandiseGroupRepository>,
    rbac: Arc<RbacRepository>,
}

impl GroupService {
    pub fn new(
        pool: PgPool,
        groups: Arc<MerchandiseGroupRepository>,
        rbac: Arc<RbacRepository>,
    ) -> Self {
        Self { pool, groups, rbac }
    }

    /// Upsert a group and ensure `group/creator` for the row's `created_by`.
    ///
    /// Callers are responsible for authorization (`merch.create` on the event)
    /// and forcing `req.user_id` to the verified caller before calling.
    /// On upsert conflict, `created_by` is preserved; we still ensure a
    /// `group/creator` row exists for the actual `created_by` (idempotent).
    pub async fn create(&self, req: &CreateGroupRequest) -> Result<MerchandiseGroup, AppError> {
        let mut tx = self.pool.begin().await?;
        let group = self.groups.create_in_tx(&mut tx, req).await?;
        if let Some(creator_id) = group.created_by {
            self.rbac
                .assign_group_creator(&mut tx, creator_id, group.id)
                .await?;
        }
        tx.commit().await?;
        Ok(group)
    }

    /// Transfer group ownership: set `created_by` and swap the group-scoped
    /// `creator` role under a row lock.
    ///
    /// Callers should pre-check group existence, target-user validity, and
    /// authorization; this method re-validates ownership for
    /// [`TransferCaller::SelfService`] under the lock so concurrent transfers
    /// stay correct (#445).
    pub async fn transfer_creator(
        &self,
        event_id: i32,
        group_name: &str,
        new_creator_id: i32,
        caller: TransferCaller,
    ) -> Result<(), AppError> {
        let mut tx = self.pool.begin().await?;
        let locked = self
            .groups
            .lock_for_update(&mut *tx, event_id, group_name)
            .await?
            .ok_or_else(|| AppError::not_found("Group not found"))?;
        let (group_id, locked_previous) = locked;

        if let TransferCaller::SelfService {
            expected_creator_id,
        } = caller
            && locked_previous != Some(expected_creator_id)
        {
            return Err(AppError::forbidden(
                "Only the group creator can transfer ownership",
            ));
        }

        if locked_previous == Some(new_creator_id) {
            return Err(AppError::bad_request("User is already the group creator"));
        }

        let updated = self
            .groups
            .set_creator(&mut *tx, event_id, group_name, new_creator_id)
            .await?;
        if !updated {
            return Err(AppError::not_found("Group not found"));
        }
        self.rbac
            .transfer_group_creator_role(&mut tx, group_id, locked_previous, new_creator_id)
            .await?;
        tx.commit().await?;
        Ok(())
    }
}
