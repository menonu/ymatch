//! [`RbacService`] — the authorization decision point for the RBAC model.
//!
//! This is the single entry point handlers will use (in a later PR) to check
//! a scoped permission: `rbac_service.check(&user, &Scope::Event(eid),
//! Permission::EventEdit)`. It composes the static
//! [`crate::services::permission_catalog::PermissionCatalog`] (role -> permission
//! map, loaded once at startup) with a per-decision
//! [`crate::repositories::rbac::RbacRepository`] query for the user's current
//! role assignments.
//!
//! ## Decision rule (ADR 0004)
//!
//! A check passes if **any** of:
//! 1. **Admin superuser bypass** — the user holds the `global/admin` role.
//! 2. The user holds a role (across the `global` scope plus the relevant
//!    `event` scope, when checking an event permission) that grants the
//!    requested permission, *or* grants the corresponding global `*.any`
//!    override (e.g. `event.edit.any` satisfies an `event.edit` check).
//!
//! The `*.any` overlap is encoded in [`Permission::satisfying_names`], not in
//! the catalog, so adding a new `*.any` permission is a catalog row, not a
//! code change to the catalog structure.
//!
//! ## Ban / verify
//!
//! [`RbacService::check`] takes a [`VerifiedUser`] that the caller has already
//! run through [`crate::services::permissions::PermissionPolicy::verify_active`]
//! (which checks existence and ban state). The service does not re-check ban
//! status — that is the caller's contract, matching how the removed
//! `require_role` / `require_owner_or_role` role-list checks used to work.

use crate::error::AppError;
use crate::repositories::rbac::RbacRepository;
use crate::repositories::user::VerifiedUser;
use crate::services::permission_catalog::PermissionCatalog;
use sqlx::PgPool;
use std::sync::Arc;
use tokio::sync::OnceCell;

/// A typed permission. The string form ([`Permission::as_str`]) is the value
/// stored in the `permissions.name` column; this enum is the type-safe handle
/// used at handler call sites. Adding a permission is a new variant *and* a
/// new seeded `permissions` row (migration).
///
/// `*.any` permissions are global-scope overrides that satisfy the
/// corresponding event-scope permission — see [`Permission::satisfying_names`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Permission {
    // --- global scope ---
    /// Read detailed user records (admin inspection). Granted to admin +
    /// moderator. Gates `GET /admin/users/:id` which returns the full User
    /// proto including sensitive fields (`device_token`, ban state, …).
    UserRead,
    /// Ban a user. Granted to admin + moderator.
    UserBan,
    /// Lift a ban. Granted to admin + moderator.
    UserUnban,
    /// Change a user's global role. Granted to admin.
    UserRoleManage,
    /// Create a new event. Granted to admin + moderator (not user).
    EventCreate,
    /// Edit any event (global override of `EventEdit`). Admin + moderator.
    EventEditAny,
    /// Delete any event (global override of `EventDelete`). Admin + moderator.
    EventDeleteAny,
    /// Delete any merch (global override of `MerchDelete`). Admin + moderator.
    MerchDeleteAny,
    /// Create merch in any event (global override of `MerchCreate`).
    /// Moderator + admin.
    MerchCreateAny,
    /// Edit any merch (global override of `MerchEdit`). Admin + moderator.
    MerchEditAny,
    /// Edit any group in any event (global override of `GroupEdit`).
    /// Admin + moderator.
    GroupEditAny,
    /// Remove any group in any event. Admin + moderator.
    GroupDelete,
    /// Delete a match (global moderation action). Admin + moderator.
    /// Has no `*.any` form — it is itself the global-scope permission.
    MatchDelete,
    /// Transfer event ownership (`events.creator_id` + `event/creator` role).
    /// Admin + moderator. Gates `PUT /admin/events/:id/creator` (#432).
    EventCreatorTransfer,
    /// Transfer item-group ownership (`merchandise_groups.created_by`).
    /// Admin + moderator. Gates `PUT /admin/events/:id/groups/:name/creator` (#432).
    GroupCreatorTransfer,
    /// List/assign/revoke event editors via the **admin** members path.
    /// Admin + moderator. Deliberately separate from [`Permission::EventMemberManage`]
    /// (no `*.any` override on that permission) so the public
    /// `/events/:id/members` API stays event creator/editor + admin-bypass
    /// only; moderators use this admin path (#432 / #442).
    EventMemberManageAny,
    /// Toggle service kill-switches. Admin.
    SystemKillSwitch,
    // --- event scope ---
    /// Edit a specific event (rename, publish). Event creator + editor.
    EventEdit,
    /// Delete a specific event. Event creator.
    EventDelete,
    /// Manage editor roles for a specific event. Event creator + editor (#442).
    EventMemberManage,
    /// Delete merch in a specific event. Event creator + editor.
    MerchDelete,
    /// Create merch in a specific event. Event creator + editor.
    MerchCreate,
    /// Edit merch in a specific event (update, publish). Event creator +
    /// editor. The merch *creator* passes via an ownership short-circuit in
    /// the handler, not via this permission.
    MerchEdit,
    /// Edit a group in a specific event (event-scope) **or** a specific item
    /// group (group-scope, #443). Event creator + editor hold the event-scoped
    /// grant; group creator + editor hold the group-scoped grant. The group
    /// *owner* (`created_by`) also passes via an ownership short-circuit in
    /// the handler.
    GroupEdit,
    /// Manage editor roles for a specific item group. Group creator + editor
    /// (#443). No `*.any` override — public path only; staff use admin
    /// group-creator transfer (#432), not this permission.
    GroupMemberManage,
}

impl Permission {
    /// The value stored in the `permissions.name` column.
    pub fn as_str(&self) -> &'static str {
        match self {
            Permission::UserRead => "user.read",
            Permission::UserBan => "user.ban",
            Permission::UserUnban => "user.unban",
            Permission::UserRoleManage => "user.role.manage",
            Permission::EventCreate => "event.create",
            Permission::EventEditAny => "event.edit.any",
            Permission::EventDeleteAny => "event.delete.any",
            Permission::MerchDeleteAny => "merch.delete.any",
            Permission::MerchCreateAny => "merch.create.any",
            Permission::MerchEditAny => "merch.edit.any",
            Permission::GroupEditAny => "group.edit.any",
            Permission::GroupDelete => "group.delete",
            Permission::MatchDelete => "match.delete",
            Permission::EventCreatorTransfer => "event.creator.transfer",
            Permission::GroupCreatorTransfer => "group.creator.transfer",
            Permission::EventMemberManageAny => "event.member.manage.any",
            Permission::SystemKillSwitch => "system.kill_switch",
            Permission::EventEdit => "event.edit",
            Permission::EventDelete => "event.delete",
            Permission::EventMemberManage => "event.member.manage",
            Permission::MerchDelete => "merch.delete",
            Permission::MerchCreate => "merch.create",
            Permission::MerchEdit => "merch.edit",
            Permission::GroupEdit => "group.edit",
            Permission::GroupMemberManage => "group.member.manage",
        }
    }

    /// The permission names that satisfy this check: the permission itself,
    /// plus — for event-scope permissions that have a global `*.any` override —
    /// that override. A global moderator's `event.edit.any` permission thus
    /// satisfies an `EventEdit` check without the moderator holding an
    /// event-scoped role.
    ///
    /// `EventMemberManage` and `GroupMemberManage` have no `*.any` override by
    /// design: only the scoped creator/editor (and the admin superuser bypass)
    /// can manage editors on the public path. Moderators use
    /// [`Permission::EventMemberManageAny`] on the admin event-members path
    /// (#432 / #442); group member management has no separate admin path yet
    /// (#443).
    pub fn satisfying_names(&self) -> &'static [&'static str] {
        match self {
            Permission::EventEdit => &["event.edit", "event.edit.any"],
            Permission::EventDelete => &["event.delete", "event.delete.any"],
            Permission::MerchDelete => &["merch.delete", "merch.delete.any"],
            Permission::MerchCreate => &["merch.create", "merch.create.any"],
            Permission::MerchEdit => &["merch.edit", "merch.edit.any"],
            // Name collision across scopes is intentional: both event-scoped
            // and group-scoped `group.edit` rows share this string; the scope
            // of the check selects which role rows are loaded (#443).
            Permission::GroupEdit => &["group.edit", "group.edit.any"],
            Permission::UserRead => &["user.read"],
            Permission::UserBan => &["user.ban"],
            Permission::UserUnban => &["user.unban"],
            Permission::UserRoleManage => &["user.role.manage"],
            Permission::EventCreate => &["event.create"],
            Permission::EventEditAny => &["event.edit.any"],
            Permission::EventDeleteAny => &["event.delete.any"],
            Permission::MerchDeleteAny => &["merch.delete.any"],
            Permission::MerchCreateAny => &["merch.create.any"],
            Permission::MerchEditAny => &["merch.edit.any"],
            Permission::GroupEditAny => &["group.edit.any"],
            Permission::GroupDelete => &["group.delete"],
            Permission::MatchDelete => &["match.delete"],
            Permission::EventCreatorTransfer => &["event.creator.transfer"],
            Permission::GroupCreatorTransfer => &["group.creator.transfer"],
            // Not an override of EventMemberManage — separate admin-path permission.
            Permission::EventMemberManageAny => &["event.member.manage.any"],
            Permission::SystemKillSwitch => &["system.kill_switch"],
            Permission::EventMemberManage => &["event.member.manage"],
            Permission::GroupMemberManage => &["group.member.manage"],
        }
    }
}

/// The scope a permission is checked against.
///
/// `Global` covers platform-wide permissions (`user.ban`, `event.create`,
/// etc.). `Event(event_id)` covers permissions scoped to a single event
/// (`event.edit`, `merch.delete`, ...). `Group(group_id)` covers permissions
/// scoped to a single item group (`merchandise_groups.id`, #443). A `Global`
/// check consults global roles only; `Event` / `Group` checks consult the
/// user's global roles *plus* their roles in that scope (so a global
/// moderator's `*.any` permission can satisfy an event-scope check).
#[derive(Debug, Clone, Copy)]
pub enum Scope {
    Global,
    Event(i32),
    /// `merchandise_groups.id` — group-scoped creator/editor (#443).
    Group(i32),
}

/// Authorization service. Construct once at startup with the shared
/// [`RbacRepository`] and the pool, and inject into handler state via
/// `Arc<RbacService>`.
///
/// The [`PermissionCatalog`] is loaded lazily on the first `check` (held in a
/// [`OnceCell`]) rather than awaited at router construction, so `create_router`
/// can stay synchronous — it is called from ~150 sync call sites in the
/// integration tests. The catalog is static between migrations, so a single
/// load is sufficient for the process lifetime.
#[derive(Clone)]
pub struct RbacService {
    rbac: Arc<RbacRepository>,
    pool: PgPool,
    catalog: Arc<OnceCell<PermissionCatalog>>,
}

impl RbacService {
    pub fn new(rbac: Arc<RbacRepository>, pool: PgPool) -> Self {
        Self {
            rbac,
            pool,
            catalog: Arc::new(OnceCell::new()),
        }
    }

    /// Load the catalog on first use, then return the cached snapshot.
    async fn catalog(&self) -> Result<&PermissionCatalog, AppError> {
        self.catalog
            .get_or_try_init(|| PermissionCatalog::load(&self.pool))
            .await
    }

    /// Pure decision logic, separated from the DB query so it can be unit
    /// tested with a hand-built catalog and injected role ids. Returns
    /// `Ok(())` if the role ids (already fetched for the relevant scopes)
    /// satisfy `permission` under `catalog`, else
    /// [`AppError::Forbidden`] with the missing permission name.
    pub fn evaluate(
        role_ids: &[i32],
        catalog: &PermissionCatalog,
        permission: Permission,
    ) -> Result<(), AppError> {
        // 1. Admin superuser bypass.
        if catalog.is_admin(role_ids) {
            return Ok(());
        }
        // 2. Any role the user holds (across the relevant scopes) grants the
        //    permission or its `*.any` override.
        let held = catalog.permissions_for_roles(role_ids);
        if permission
            .satisfying_names()
            .iter()
            .any(|name| held.contains(*name))
        {
            Ok(())
        } else {
            Err(AppError::forbidden(format!(
                "Missing permission: {}",
                permission.as_str()
            )))
        }
    }

    /// Check that `user` (already verified active by the caller) holds
    /// `permission` in `scope`. Queries the user's current role assignments
    /// for the relevant scopes and applies [`Self::evaluate`].
    pub async fn check(
        &self,
        user: &VerifiedUser,
        scope: &Scope,
        permission: Permission,
    ) -> Result<(), AppError> {
        let role_ids = self.rbac.role_ids_for_user(user.id, scope).await?;
        let catalog = self.catalog().await?;
        Self::evaluate(&role_ids, catalog, permission)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::repositories::user::VerifiedUser;
    use crate::services::permission_catalog::PermissionCatalog;
    use sqlx::PgPool;
    use std::collections::{HashMap, HashSet};

    /// Role ids used by the hand-built test catalog. These mirror the seeded
    /// ids but are arbitrary for the pure `evaluate` tests — only the
    /// role->permission mapping matters, not the numeric ids.
    const ADMIN: i32 = 1;
    const MODERATOR: i32 = 2;
    const USER: i32 = 3;
    const CREATOR: i32 = 4;
    const EDITOR: i32 = 5;
    const GROUP_CREATOR: i32 = 6;
    const GROUP_EDITOR: i32 = 7;

    fn set(names: &[&str]) -> HashSet<String> {
        names.iter().map(|s| s.to_string()).collect()
    }

    /// The full seeded permission matrix, as an in-memory catalog, so
    /// `evaluate` can be exercised without a database.
    fn test_catalog() -> PermissionCatalog {
        let mut perms_by_role: HashMap<i32, HashSet<String>> = HashMap::new();
        perms_by_role.insert(
            ADMIN,
            set(&[
                "user.read",
                "user.ban",
                "user.unban",
                "user.role.manage",
                "event.create",
                "event.edit.any",
                "event.delete.any",
                "merch.delete.any",
                "merch.create.any",
                "merch.edit.any",
                "group.edit.any",
                "group.delete",
                "match.delete",
                "event.creator.transfer",
                "group.creator.transfer",
                "event.member.manage.any",
                "system.kill_switch",
            ]),
        );
        perms_by_role.insert(
            MODERATOR,
            set(&[
                "user.read",
                "user.ban",
                "user.unban",
                "event.create",
                "event.edit.any",
                "event.delete.any",
                "merch.delete.any",
                "merch.create.any",
                "merch.edit.any",
                "group.edit.any",
                "group.delete",
                "match.delete",
                "event.creator.transfer",
                "group.creator.transfer",
                "event.member.manage.any",
            ]),
        );
        perms_by_role.insert(USER, HashSet::new());
        perms_by_role.insert(
            CREATOR,
            set(&[
                "event.edit",
                "event.delete",
                "event.member.manage",
                "merch.delete",
                "merch.create",
                "merch.edit",
                "group.edit",
            ]),
        );
        perms_by_role.insert(
            EDITOR,
            set(&[
                "event.edit",
                "event.member.manage",
                "merch.delete",
                "merch.create",
                "merch.edit",
                "group.edit",
            ]),
        );
        perms_by_role.insert(GROUP_CREATOR, set(&["group.edit", "group.member.manage"]));
        perms_by_role.insert(GROUP_EDITOR, set(&["group.edit", "group.member.manage"]));
        PermissionCatalog::new(ADMIN, perms_by_role)
    }

    fn ok(role_ids: &[i32], perm: Permission) {
        assert!(
            RbacService::evaluate(role_ids, &test_catalog(), perm).is_ok(),
            "expected {perm:?} ({}) to be allowed for roles {role_ids:?}",
            perm.as_str()
        );
    }

    fn denied(role_ids: &[i32], perm: Permission) {
        assert!(
            RbacService::evaluate(role_ids, &test_catalog(), perm).is_err(),
            "expected {perm:?} ({}) to be DENIED for roles {role_ids:?}",
            perm.as_str()
        );
    }

    // --- Permission::satisfying_names ---

    #[test]
    fn satisfying_names_includes_any_override_for_event_scope() {
        assert_eq!(
            Permission::EventEdit.satisfying_names(),
            &["event.edit", "event.edit.any"]
        );
        assert_eq!(
            Permission::EventDelete.satisfying_names(),
            &["event.delete", "event.delete.any"]
        );
        assert_eq!(
            Permission::MerchDelete.satisfying_names(),
            &["merch.delete", "merch.delete.any"]
        );
        assert_eq!(
            Permission::MerchCreate.satisfying_names(),
            &["merch.create", "merch.create.any"]
        );
        assert_eq!(
            Permission::MerchEdit.satisfying_names(),
            &["merch.edit", "merch.edit.any"]
        );
        assert_eq!(
            Permission::GroupEdit.satisfying_names(),
            &["group.edit", "group.edit.any"]
        );
    }

    #[test]
    fn satisfying_names_for_match_delete_is_just_the_name() {
        // `match.delete` is itself a global-scope permission (granted to admin
        // + moderator), so it has no `*.any` override — its satisfying set is
        // just itself.
        assert_eq!(
            Permission::MatchDelete.satisfying_names(),
            &["match.delete"]
        );
    }

    #[test]
    fn satisfying_names_has_no_any_override_for_member_manage() {
        // event.member.manage deliberately has no *.any override: creator +
        // editor (or the admin bypass) on the public path; moderators use
        // EventMemberManageAny on the admin path (#432 / #442).
        assert_eq!(
            Permission::EventMemberManage.satisfying_names(),
            &["event.member.manage"]
        );
        // group.member.manage likewise has no *.any (#443).
        assert_eq!(
            Permission::GroupMemberManage.satisfying_names(),
            &["group.member.manage"]
        );
    }

    #[test]
    fn satisfying_names_for_global_permissions_is_just_the_name() {
        assert_eq!(Permission::UserRead.satisfying_names(), &["user.read"]);
        assert_eq!(Permission::UserBan.satisfying_names(), &["user.ban"]);
        assert_eq!(
            Permission::UserRoleManage.satisfying_names(),
            &["user.role.manage"]
        );
        assert_eq!(
            Permission::EventCreate.satisfying_names(),
            &["event.create"]
        );
        assert_eq!(
            Permission::SystemKillSwitch.satisfying_names(),
            &["system.kill_switch"]
        );
    }

    // --- admin superuser bypass ---

    #[test]
    fn admin_bypass_passes_every_permission() {
        ok(&[ADMIN], Permission::UserBan);
        ok(&[ADMIN], Permission::UserRoleManage);
        ok(&[ADMIN], Permission::SystemKillSwitch);
        ok(&[ADMIN], Permission::EventEdit);
        ok(&[ADMIN], Permission::EventMemberManage);
        ok(&[ADMIN], Permission::MerchDelete);
        ok(&[ADMIN], Permission::MerchCreate);
        ok(&[ADMIN], Permission::MerchEdit);
        ok(&[ADMIN], Permission::GroupEdit);
        ok(&[ADMIN], Permission::GroupMemberManage);
        ok(&[ADMIN], Permission::MatchDelete);
    }

    #[test]
    fn admin_combined_with_other_role_still_bypasses() {
        ok(&[CREATOR, ADMIN], Permission::SystemKillSwitch);
    }

    // --- moderator: global *.any satisfies event-scope checks ---

    #[test]
    fn moderator_can_edit_any_event_via_any_override() {
        ok(&[MODERATOR], Permission::EventEdit);
        ok(&[MODERATOR], Permission::EventDelete);
        ok(&[MODERATOR], Permission::MerchDelete);
        ok(&[MODERATOR], Permission::MerchCreate);
        ok(&[MODERATOR], Permission::MerchEdit);
        ok(&[MODERATOR], Permission::GroupEdit);
    }

    #[test]
    fn moderator_can_delete_any_match() {
        // match.delete is global, granted to moderator + admin directly.
        ok(&[MODERATOR], Permission::MatchDelete);
        denied(&[CREATOR], Permission::MatchDelete);
        denied(&[EDITOR], Permission::MatchDelete);
        denied(&[USER], Permission::MatchDelete);
    }

    #[test]
    fn moderator_can_delete_any_group() {
        // #380: group.delete is global, granted to moderator + admin directly.
        ok(&[MODERATOR], Permission::GroupDelete);
        denied(&[CREATOR], Permission::GroupDelete);
        denied(&[EDITOR], Permission::GroupDelete);
        denied(&[USER], Permission::GroupDelete);
    }

    #[test]
    fn moderator_can_read_user_details() {
        // #376: user.read is global, granted to moderator + admin directly.
        ok(&[MODERATOR], Permission::UserRead);
        ok(&[ADMIN], Permission::UserRead);
        denied(&[CREATOR], Permission::UserRead);
        denied(&[EDITOR], Permission::UserRead);
        denied(&[USER], Permission::UserRead);
    }

    #[test]
    fn moderator_cannot_manage_event_members_via_creator_permission() {
        // No *.any override for event.member.manage; moderator is not the creator.
        // Admin staff use EventMemberManageAny on the admin members path instead (#432).
        denied(&[MODERATOR], Permission::EventMemberManage);
        ok(&[MODERATOR], Permission::EventMemberManageAny);
        ok(&[ADMIN], Permission::EventMemberManageAny);
        denied(&[CREATOR], Permission::EventMemberManageAny);
        denied(&[USER], Permission::EventMemberManageAny);
    }

    #[test]
    fn moderator_can_transfer_event_and_group_creators() {
        // #432: global staff can reassign ownership via admin endpoints.
        ok(&[MODERATOR], Permission::EventCreatorTransfer);
        ok(&[MODERATOR], Permission::GroupCreatorTransfer);
        ok(&[ADMIN], Permission::EventCreatorTransfer);
        ok(&[ADMIN], Permission::GroupCreatorTransfer);
        denied(&[CREATOR], Permission::EventCreatorTransfer);
        denied(&[EDITOR], Permission::GroupCreatorTransfer);
        denied(&[USER], Permission::EventCreatorTransfer);
    }

    #[test]
    fn moderator_global_permissions() {
        ok(&[MODERATOR], Permission::UserRead);
        ok(&[MODERATOR], Permission::UserBan);
        ok(&[MODERATOR], Permission::UserUnban);
        ok(&[MODERATOR], Permission::EventCreate);
        denied(&[MODERATOR], Permission::UserRoleManage);
        denied(&[MODERATOR], Permission::SystemKillSwitch);
    }

    // --- event creator ---

    #[test]
    fn creator_can_manage_their_event() {
        ok(&[CREATOR], Permission::EventEdit);
        ok(&[CREATOR], Permission::EventDelete);
        ok(&[CREATOR], Permission::EventMemberManage);
        ok(&[CREATOR], Permission::MerchDelete);
        ok(&[CREATOR], Permission::MerchCreate);
        ok(&[CREATOR], Permission::MerchEdit);
        ok(&[CREATOR], Permission::GroupEdit);
    }

    #[test]
    fn creator_cannot_ban_or_create_events_globally() {
        denied(&[CREATOR], Permission::UserBan);
        denied(&[CREATOR], Permission::EventCreate);
    }

    // --- event editor ---

    // --- group creator / editor (#443) ---

    #[test]
    fn group_creator_and_editor_can_edit_group_and_manage_members() {
        ok(&[GROUP_CREATOR], Permission::GroupEdit);
        ok(&[GROUP_CREATOR], Permission::GroupMemberManage);
        ok(&[GROUP_EDITOR], Permission::GroupEdit);
        ok(&[GROUP_EDITOR], Permission::GroupMemberManage);
        // Group roles do not grant event-scoped powers.
        denied(&[GROUP_CREATOR], Permission::EventEdit);
        denied(&[GROUP_EDITOR], Permission::EventMemberManage);
        denied(&[GROUP_CREATOR], Permission::MerchCreate);
        denied(&[USER], Permission::GroupMemberManage);
        denied(&[MODERATOR], Permission::GroupMemberManage);
    }

    #[test]
    fn editor_can_edit_and_manage_members_but_not_delete() {
        // #442: editors may manage other editors (event.member.manage).
        ok(&[EDITOR], Permission::EventEdit);
        ok(&[EDITOR], Permission::MerchDelete);
        ok(&[EDITOR], Permission::MerchCreate);
        ok(&[EDITOR], Permission::MerchEdit);
        ok(&[EDITOR], Permission::GroupEdit);
        ok(&[EDITOR], Permission::EventMemberManage);
        denied(&[EDITOR], Permission::EventDelete);
        denied(&[EDITOR], Permission::UserBan);
        denied(&[EDITOR], Permission::MatchDelete);
    }

    // --- plain user / no assignment ---

    #[test]
    fn plain_user_has_no_elevated_permissions() {
        denied(&[USER], Permission::UserRead);
        denied(&[USER], Permission::UserBan);
        denied(&[USER], Permission::EventCreate);
        denied(&[USER], Permission::EventEdit);
        denied(&[USER], Permission::MerchDelete);
        denied(&[USER], Permission::MerchCreate);
        denied(&[USER], Permission::MerchEdit);
        denied(&[USER], Permission::GroupEdit);
        denied(&[USER], Permission::MatchDelete);
    }

    #[test]
    fn no_roles_denies_everything_elevated() {
        denied(&[], Permission::UserBan);
        denied(&[], Permission::EventEdit);
        denied(&[], Permission::EventMemberManage);
    }

    #[test]
    fn denied_returns_forbidden_with_permission_name() {
        let err = RbacService::evaluate(&[], &test_catalog(), Permission::EventEdit).unwrap_err();
        match err {
            AppError::Forbidden(msg) => assert!(
                msg.contains("event.edit"),
                "forbidden message should name the missing permission, got: {msg}"
            ),
            other => panic!("expected Forbidden, got {other:?}"),
        }
    }

    // --- combination: global moderator + event editor ---

    #[test]
    fn moderator_plus_editor_combines_permissions() {
        // editor grants event.edit; moderator would also grant it via .any.
        ok(&[MODERATOR, EDITOR], Permission::EventEdit);
        // #442: editor grants event.member.manage; moderator alone still does not
        // (no *.any override — staff use EventMemberManageAny on admin path).
        ok(&[MODERATOR, EDITOR], Permission::EventMemberManage);
        denied(&[MODERATOR], Permission::EventMemberManage);
    }

    // --- integration: RbacService::check against a real seeded DB ---

    fn verified(id: i32) -> VerifiedUser {
        VerifiedUser {
            id,
            is_banned: false,
        }
    }

    async fn role_id(pool: &PgPool, scope_type: &str, name: &str) -> i32 {
        sqlx::query_scalar("SELECT id FROM roles WHERE scope_type = $1 AND name = $2")
            .bind(scope_type)
            .bind(name)
            .fetch_one(pool)
            .await
            .unwrap()
    }

    async fn assign(
        pool: &PgPool,
        user_id: i32,
        scope_type: &str,
        scope_id: Option<i32>,
        role: &str,
    ) {
        let rid = role_id(pool, scope_type, role).await;
        sqlx::query(
            "INSERT INTO user_roles (user_id, role_id, scope_type, scope_id)
             VALUES ($1, $2, $3, $4)",
        )
        .bind(user_id)
        .bind(rid)
        .bind(scope_type)
        .bind(scope_id)
        .execute(pool)
        .await
        .unwrap();
    }

    /// `#[sqlx::test]` provisions a fresh DB with all migrations applied, so
    /// the RBAC catalog (roles/permissions/role_permissions) is already seeded
    /// and `PermissionCatalog::load` succeeds lazily on the first check.
    #[sqlx::test]
    async fn check_against_seeded_db(pool: PgPool) {
        let rbac = Arc::new(RbacRepository::new(pool.clone()));
        let service = RbacService::new(rbac.clone(), pool.clone());

        // Four users: admin, moderator, plain user, and a future editor.
        for name in ["rbac-admin", "rbac-mod", "rbac-user", "rbac-editor"] {
            sqlx::query("INSERT INTO users (username) VALUES ($1)")
                .bind(name)
                .execute(&pool)
                .await
                .unwrap();
        }
        let admin_id: i32 =
            sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-admin'")
                .fetch_one(&pool)
                .await
                .unwrap();
        let mod_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-mod'")
            .fetch_one(&pool)
            .await
            .unwrap();
        let user_id: i32 = sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-user'")
            .fetch_one(&pool)
            .await
            .unwrap();
        let editor_id: i32 =
            sqlx::query_scalar("SELECT id FROM users WHERE username = 'rbac-editor'")
                .fetch_one(&pool)
                .await
                .unwrap();

        // An event the editor is a member of (created by admin; the creator
        // role is assigned explicitly below rather than auto-derived).
        sqlx::query("INSERT INTO events (name, creator_id) VALUES ('RBAC Event', $1)")
            .bind(admin_id)
            .execute(&pool)
            .await
            .unwrap();
        let event_id: i32 = sqlx::query_scalar("SELECT id FROM events WHERE name = 'RBAC Event'")
            .fetch_one(&pool)
            .await
            .unwrap();
        // A second event owned by user_id, which admin is NOT a member of.
        // This isolates the admin superuser bypass: EventMemberManage is
        // granted via event creator/editor roles (not *.any), and user_id
        // (not admin) is the creator, so admin can only pass via the bypass
        // -- not via an event role.
        sqlx::query("INSERT INTO events (name, creator_id) VALUES ('Other Event', $1)")
            .bind(user_id)
            .execute(&pool)
            .await
            .unwrap();
        let other_event_id: i32 =
            sqlx::query_scalar("SELECT id FROM events WHERE name = 'Other Event'")
                .fetch_one(&pool)
                .await
                .unwrap();

        // Assign global roles.
        assign(&pool, admin_id, "global", None, "admin").await;
        assign(&pool, mod_id, "global", None, "moderator").await;
        // user_id is the creator of Other Event (so the bypass test below is
        // against a real creator, not an ownerless event).
        assign(&pool, user_id, "event", Some(other_event_id), "creator").await;
        // editor is scoped to event_id only.
        assign(&pool, editor_id, "event", Some(event_id), "editor").await;

        // Admin superuser bypass: passes a global permission and an
        // event-scoped permission (EventMemberManage) on an event admin does
        // NOT own (user_id does).
        assert!(
            service
                .check(&verified(admin_id), &Scope::Global, Permission::UserBan)
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(admin_id),
                    &Scope::Event(other_event_id),
                    Permission::EventMemberManage
                )
                .await
                .is_ok()
        );

        // Moderator: global ban + event.create, can edit any event via .any,
        // but cannot manage event members or change roles.
        assert!(
            service
                .check(&verified(mod_id), &Scope::Global, Permission::UserBan)
                .await
                .is_ok()
        );
        assert!(
            service
                .check(&verified(mod_id), &Scope::Global, Permission::EventCreate)
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(mod_id),
                    &Scope::Global,
                    Permission::UserRoleManage
                )
                .await
                .is_err()
        );
        assert!(
            service
                .check(
                    &verified(mod_id),
                    &Scope::Event(event_id),
                    Permission::EventEdit
                )
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(mod_id),
                    &Scope::Event(event_id),
                    Permission::EventMemberManage
                )
                .await
                .is_err()
        );

        // Plain user: no global role, so cannot create events or ban. They are
        // the creator of Other Event (but not event_id), so they can manage
        // members on Other Event and are denied on event_id.
        assert!(
            service
                .check(&verified(user_id), &Scope::Global, Permission::EventCreate)
                .await
                .is_err()
        );
        assert!(
            service
                .check(&verified(user_id), &Scope::Global, Permission::UserBan)
                .await
                .is_err()
        );
        assert!(
            service
                .check(
                    &verified(user_id),
                    &Scope::Event(event_id),
                    Permission::EventEdit
                )
                .await
                .is_err()
        );
        // user_id is the creator of Other Event -> EventMemberManage passes.
        assert!(
            service
                .check(
                    &verified(user_id),
                    &Scope::Event(other_event_id),
                    Permission::EventMemberManage
                )
                .await
                .is_ok()
        );

        // Editor: can edit and delete merch on their event, can manage members
        // (#442), cannot delete the event, and has no power on the other event.
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::EventEdit
                )
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::MerchDelete
                )
                .await
                .is_ok()
        );
        // Editor can create merch on their event (event/merch.create).
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::MerchCreate
                )
                .await
                .is_ok()
        );
        // Editor can edit merch on their event (event/merch.edit); the merch
        // *creator* ownership short-circuit lives in the handler, not here.
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::MerchEdit
                )
                .await
                .is_ok()
        );
        // Editor can edit groups on their event (event/group.edit).
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::GroupEdit
                )
                .await
                .is_ok()
        );
        // A plain user cannot edit merch/groups on an event they have no role on.
        assert!(
            service
                .check(
                    &verified(user_id),
                    &Scope::Event(event_id),
                    Permission::MerchEdit
                )
                .await
                .is_err()
        );
        assert!(
            service
                .check(
                    &verified(user_id),
                    &Scope::Event(event_id),
                    Permission::GroupEdit
                )
                .await
                .is_err()
        );
        // A moderator edits any event's merch/groups via the `*.any` override.
        assert!(
            service
                .check(
                    &verified(mod_id),
                    &Scope::Event(event_id),
                    Permission::MerchEdit
                )
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(mod_id),
                    &Scope::Event(event_id),
                    Permission::GroupEdit
                )
                .await
                .is_ok()
        );
        // match.delete is a global moderation action: moderator ok, plain user
        // denied, admin ok via the bypass.
        assert!(
            service
                .check(&verified(mod_id), &Scope::Global, Permission::MatchDelete)
                .await
                .is_ok()
        );
        assert!(
            service
                .check(&verified(user_id), &Scope::Global, Permission::MatchDelete)
                .await
                .is_err()
        );
        assert!(
            service
                .check(&verified(admin_id), &Scope::Global, Permission::MatchDelete)
                .await
                .is_ok()
        );
        // #376: user.read — moderator/admin ok, plain user denied.
        assert!(
            service
                .check(&verified(mod_id), &Scope::Global, Permission::UserRead)
                .await
                .is_ok()
        );
        assert!(
            service
                .check(&verified(user_id), &Scope::Global, Permission::UserRead)
                .await
                .is_err()
        );
        assert!(
            service
                .check(&verified(admin_id), &Scope::Global, Permission::UserRead)
                .await
                .is_ok()
        );
        // Moderator can create merch on any event via merch.create.any.
        assert!(
            service
                .check(
                    &verified(mod_id),
                    &Scope::Event(event_id),
                    Permission::MerchCreate
                )
                .await
                .is_ok()
        );
        // Plain user cannot create merch (no event role, no global override).
        assert!(
            service
                .check(
                    &verified(user_id),
                    &Scope::Event(event_id),
                    Permission::MerchCreate
                )
                .await
                .is_err()
        );
        // Admin superuser bypass: create merch on an event admin does not own.
        assert!(
            service
                .check(
                    &verified(admin_id),
                    &Scope::Event(other_event_id),
                    Permission::MerchCreate
                )
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::EventDelete
                )
                .await
                .is_err()
        );
        // #442: event editor holds event.member.manage.
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(event_id),
                    Permission::EventMemberManage
                )
                .await
                .is_ok()
        );
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Event(other_event_id),
                    Permission::EventEdit
                )
                .await
                .is_err()
        );

        // A pure-global check ignores event-scoped roles: the editor has no
        // global permissions, so a Global EventEdit... is not a thing (EventEdit
        // is event-scoped), but UserRoleManage (global) is denied for editor.
        assert!(
            service
                .check(
                    &verified(editor_id),
                    &Scope::Global,
                    Permission::UserRoleManage
                )
                .await
                .is_err()
        );
    }
}
