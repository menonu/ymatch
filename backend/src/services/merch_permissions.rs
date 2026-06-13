//! Merchandise-specific permission policy.
//!
//! [`MerchPermissionPolicy`] models the 3-way authorization rule that
//! `merch::delete_merch_by_creator` enforced inline before Phase 3:
//!
//! > A merch row can be deleted by its creator, by the event creator,
//! > or by an admin / moderator.
//!
//! This rule was too specific for [`PermissionPolicy`] (which only handles
//! the 2-way `owner OR role` case), so it lives in its own service. It
//! composes the user [`PermissionPolicy`] for the elevated-role checks.

use crate::error::AppError;
use crate::repositories::merch::MerchandiseRepository;
use crate::services::permissions::PermissionPolicy;
use std::sync::Arc;

/// Service for merchandise-specific permission decisions.
#[derive(Clone)]
pub struct MerchPermissionPolicy {
    users: Arc<PermissionPolicy>,
    merch: Arc<MerchandiseRepository>,
}

impl MerchPermissionPolicy {
    pub fn new(users: Arc<PermissionPolicy>, merch: Arc<MerchandiseRepository>) -> Self {
        Self { users, merch }
    }

    /// Verify the user is allowed to act on a merch row given the 3-way
    /// rule (merch creator OR event creator OR elevated role).
    ///
    /// The caller has already verified the merch row exists; this method
    /// returns `Ok(())` if the rule is satisfied and `AppError::Forbidden`
    /// otherwise.
    pub async fn require_can_modify(
        &self,
        user_id: i32,
        event_id: i32,
        merch_id: i32,
        event_creator_id: Option<i32>,
    ) -> Result<(), AppError> {
        let user = self.users.verify_active(user_id).await?;

        // Path 1: merch creator
        if let Some(Some(creator_id)) = self.merch.get_creator(event_id, merch_id).await? {
            if creator_id == user.id {
                return Ok(());
            }
        }

        // Path 2: event creator
        if let Some(ec) = event_creator_id {
            if ec == user.id {
                return Ok(());
            }
        }

        // Path 3: elevated role
        self.users.require_role(&user, &["admin", "moderator"])?;
        Ok(())
    }
}
