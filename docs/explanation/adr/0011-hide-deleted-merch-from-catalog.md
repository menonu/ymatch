# ADR 0011: Hide Soft-Deleted Merchandise from Catalog Surfaces by Default

- **Status**: Accepted
- **Date**: 2026-07-18
- **Supersedes**: —
- **Related**: Partially revises [ADR 0008](0008-merchandise-deletion-semantics.md) Decision 4 (holder-visible deleted merch on catalog lists). Does **not** reverse soft-delete, match `CANCELLED`, or historical match-detail naming. Originating issue: [#468](https://github.com/menonu/ymatch/issues/468).

## Context

[ADR 0008](0008-merchandise-deletion-semantics.md) Decision 4 made soft-deleted merchandise visible on catalog surfaces to *holders*: any user with a `HAVE` inventory row for the item, **plus** the merch `creator_id`. The frontend badged those rows as deleted and disabled trade/edit actions.

In practice, creators and moderators who delete an item (or remove a group, which soft-deletes its merch) still saw the corpse in event merch lists and related pickers. Deletion is a **rare corrective** action meant to clean up the catalog, not leave management UIs cluttered with deleted rows.

Product intent for #468:

- Soft-delete, match cancellation, and inventory history stay as in ADR 0008.
- **Default catalog visibility** of deleted rows should be **off for everyone**, including creator/moderator.
- A future “show deleted” / archive control may reintroduce optional visibility — out of scope here.

## Decision

1. **Catalog and management list APIs are live-only.**  
   Event merch list (`MerchandiseRepository::list_for_event` / `GET /api/v1/events/:id/merch`), admin merch list, search, matching, and add-merch pickers filter `is_deleted = false` for **all** viewers. Soft-deleted rows are not returned to the merch creator, event moderators/admins, `HAVE` holders, or strangers.

2. **Drop creator-as-holder for catalog visibility.**  
   Catalog visibility no longer treats `creator_id == viewer` (or any management role) as a reason to include soft-deleted merch. Draft visibility for non-deleted drafts is unchanged (`status = 'published' OR creator_id = viewer`).

3. **Holder inventory still surfaces deletion.**  
   `InventoryRepository::list_for_user` continues to join merch and return `is_deleted` so a user who still has a `HAVE`/`WANT`/`TRADE` row can see that the catalog entry is gone (badge or equivalent on inventory-driven UI). This does **not** put the row back on the event merch catalog.

4. **Historical match detail unchanged.**  
   ADR 0008 Decision 7 remains: match history may name deleted merch for participants. Soft-delete + system `CANCELLED` semantics (ADR 0008 Decisions 1–2, as extended by [ADR 0010](0010-inventory-mutual-capacity-invalidation.md)) are unchanged.

5. **Groups.**  
   Group removal already hard-deletes the `merchandise_groups` row and soft-deletes its merch (`remove_for_admin`). Removed groups stay absent from group lists. Soft-deleted merch from a removed group must not reappear on catalog lists (Decision 1).

6. **No restore / include-deleted flag in this decision.**  
   Optional query flags or UI toggles to browse deleted catalog items are deferred.

## Consequences

**Positive:**

- Creators and moderators get a clean catalog after delete — the corrective action sticks in the UI.
- One simple list filter (`is_deleted = false`) for catalog surfaces; no per-viewer holder OR on merch list.
- Soft-delete and history invariants from ADR 0008 remain intact.

**Negative / costs:**

- A pure `HAVE` holder no longer sees the deleted item on the **event merch list**; they only learn via inventory (or match history) that the catalog entry is gone. Accepted: catalog is not the inventory surface.
- Frontend deleted badges on catalog merch cards become defensive/dead for normal API responses until a future “show deleted” flag exists; inventory-side marking remains relevant.

**Follow-up work required:**

- Update `list_for_event` and ADR 0008 holder-visibility tests for the new matrix.
- Optionally add inventory UI badge if not already driven by `InventoryItem.is_deleted` (not required for acceptance if inventory API already returns the flag).
- Future issue: optional “include deleted” visibility control for moderators.

## Alternatives Considered

- **Keep ADR 0008 Decision 4 as-is (creator + HAVE see deleted catalog rows).**  
  Rejected: conflicts with the product goal that delete should clean management/catalog UIs by default.

- **Hide from creators/mods only; keep catalog visible to HAVE holders.**  
  Rejected for this change: adds asymmetric list logic for little benefit once inventory already carries `is_deleted`. Prefer uniform live-only catalog.

- **Hard-delete merch after inventory is gone.**  
  Rejected: out of scope; ADR 0008 soft-delete remains for FK history and match detail.
