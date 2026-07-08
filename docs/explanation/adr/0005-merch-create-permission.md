# ADR 0005: Gate Merch Creation Behind `merch.create`

- **Status**: Accepted
- **Date**: 2026-07-08
- **Supersedes**: —

## Context

Before this decision, `create_merch` (`backend/src/handlers/merch.rs`) had **no
authorization**: any active user could `POST /api/v1/events/:id/merch` and add
merchandise to any event. The handler only ran `verify_active` on the optional
`creator_id` (to populate the merch's owner column) and otherwise delegated
straight to the repository.

ADR 0004's permission matrix — introduced in #228 and wired through the
`RbacService` — deliberately left `create_merch` unwired (PR3a / #362). The
0004 matrix has `merch.delete` (event scope, creator + editor) and
`merch.delete.any` (global, moderator + admin) but **no** `merch.create`
permission, so there was no permission to check even once the handler was
wired.

The product decision (issue #365): merch creation should be a **curated
action** by the event owner/editors (plus platform moderators/admins), not
open participation. A regular user posting merch into someone else's event is
unwanted — events are curated by their creator and delegated editors.

The frontend `event_detail_screen.dart` shows an "Add Merch" button to every
viewer, and `MerchController.addMerch` posts without sending a caller identity.
This change is therefore a **breaking change** for the frontend: after the
backend gate ships, non-editors who click Add Merch receive a 403. Proper
frontend button gating requires a "current user's event role" endpoint that
does not exist yet (`GET /events/:id/members` is creator-only), so the button
stays visible for now and the 403 is surfaced via the existing #227 rethrow.

## Decision

Extend ADR 0004's permission model with a new event-scope permission and its
global override, and gate `create_merch` on it:

- Add `event/merch.create` ("Create merch in this event.") granted to the event
  `creator` and `editor`.
- Add `global/merch.create.any` ("Create merch in any event (global override of
  `merch.create`).") granted to `moderator` and `admin`. The admin superuser
  bypass makes admin omnipermissive regardless, but the row documents intent —
  matching how 0004 seeds admin's other `*.any` rows.
- In `create_merch`, treat `CreateMerchRequest.creator_id` as the **caller
  identity** (the merch creator = the caller) and require it: 400 if absent,
  `verify_active` (banned → 403), 404 if the event does not exist (checked
  before the RBAC check so a missing event is not leaked as a 403), then
  `RbacService::check(&user, &Scope::Event(event_id), Permission::MerchCreate)`.

This is a **supplement** to ADR 0004, not a supersede: 0004's matrix is
extended with a new permission, and 0004's body is left intact.

The data is seeded by migration `20260708000000_merch_create_permission.sql`
(idempotent `ON CONFLICT DO NOTHING`, mirroring `20260705000000_rbac.sql`). No
existing merch rows are migrated or removed — only future creation is gated.

## Consequences

- **Breaking change for the frontend:** regular users can no longer add merch
  to events they do not own/edit. The Add Merch button 403s for non-editors
  until a follow-up adds role-awareness (a "current user's event role"
  endpoint) and gates the button. Until then the 403 is surfaced via the
  existing #227 rethrow, so the user sees a real error rather than a silent
  success.
- The merch `creator_id` column is now always the authorized caller (creator /
  editor / moderator / admin), never a plain participant. Existing merch rows
  are untouched and may still have arbitrary/NULL `creator_id`; only future
  rows reflect the gate.
- `create_merch` now requires `creator_id` in the request body (previously
  optional). The frontend `addMerch` is updated to send the current user's id;
  any other client posting without it gets a 400.
- A follow-up issue is required for frontend button gating + the role-awareness
  endpoint (filed alongside this PR).
- `update_merch` / `publish_merch` are unchanged this round — they keep their
  existing `require_owner_or_role` (merch creator OR admin/mod). A future
  `merch.edit` permission could unify them with the create/delete model.

## Alternatives Considered

- **Keep merch creation open to any active user (status quo).** Rejected — the
  product wants events curated by their owner/editors, not open participation.
- **Ship backend gate and frontend gating in one PR.** Rejected for this round
  — frontend gating needs a "current user's event role" endpoint that does
  not exist yet, and `GET /events/:id/members` is creator-only. Splitting
  reduces the blast radius: the backend gate lands now (with the minimal
  frontend change of sending the caller id), and full button gating follows in
  a dedicated issue.
- **Reuse `merch.delete` to gate creation.** Rejected — `merch.delete` is the
  delete action's permission; overloading it for create would couple two
  distinct actions to one permission and make future grant changes ambiguous.
  A dedicated `merch.create` permission keeps the matrix self-describing.