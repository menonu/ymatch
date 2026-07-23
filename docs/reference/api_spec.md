# API Specification - ymatch

Base URL: `/api/v1`

All request and response bodies use JSON (`Content-Type: application/json`).

---

## 1. Authentication & Users

### POST /api/v1/auth/signup

Create a new user account.

- **Request Body**:
  ```json
  {
    "username": "user123",
    "password": "securepassword",
    "device_token": "fcm_token_..."   // optional
  }
  ```
- **Response**: `201 Created`
  ```json
  { "user_id": 1, "username": "user123" }
  ```

### POST /api/v1/auth/login

Login with username and password.

- **Request Body**:
  ```json
  { "username": "user123", "password": "securepassword" }
  ```
- **Response**: `200 OK`
  ```json
  { "user_id": 1, "username": "user123", "role": "user" }
  ```
- **Error**: `403 Forbidden` if the user is banned (response includes `ban_reason` and `banned_until`).

### POST /api/v1/auth/guest

Guest login by device UUID. Creates the guest account on first use.

- **Request Body**:
  ```json
  {
    "uuid": "device-uuid-string",
    "device_token": "fcm_token_..."   // optional
  }
  ```
- **Response**: `200 OK`
  ```json
  { "user_id": 2, "username": "guest_abc123", "role": "user" }
  ```
- **Error**: `403 Forbidden` if the guest account is banned.

### GET /api/v1/users

User directory for member pickers and the admin users tab (#491).

- **Query Parameters**:
  | Param     | Type | Description                                      |
  |-----------|------|--------------------------------------------------|
  | `user_id` | int  | Required. Active caller identity.                |
- **Authorization**:
  - Any **active** caller receives a **lean** directory (`id`, `username` only).
  - Callers with global `user.read` (moderator/admin) also receive `role` and
    ban fields. `device_token` and `uuid` are **never** returned on this list
    (use `GET /admin/users/:id` for detail inspection).
- **Response**: `200 OK`
  ```json
  [
    { "id": 1, "username": "user123", "role": "user", "is_banned": false }
  ]
  ```
- **Errors**: `400` if `user_id` missing; `403` if caller is banned; `404` if
  caller does not exist.

---

## 2. Events

### GET /api/v1/events

List events. Returns all published events plus the requesting user's own drafts.

- **Query Parameters**:
  | Param     | Type | Description                           |
  |-----------|------|---------------------------------------|
  | `user_id` | int  | Optional. Include this user's drafts. |
- **Response**: `200 OK`
  ```json
  [
    {
      "id": 1,
      "name": "Yukari Live 2025",
      "creator_id": 1,
      "created_at": "2025-07-01T00:00:00Z",
      "unique_views": 42,
      "status": "published",
      "is_favorited": true
    }
  ]
  ```

### POST /api/v1/events

Create a new event.

- **Request Body**:
  ```json
  {
    "name": "Summer Exchange 2025",
    "creator_id": 1,
    "status": "draft"               // optional, defaults to "published"
  }
  ```
- **Response**: `201 Created`
  ```json
  { "id": 2, "name": "Summer Exchange 2025", "status": "draft" }
  ```
- **Permissions**: Banned users cannot create events.

### POST /api/v1/events/:id/publish

Publish a draft event.

- **Request Body**:
  ```json
  { "user_id": 1 }
  ```
- **Response**: `200 OK`
- **Permissions**: Event owner, admin, or moderator only.

### POST /api/v1/events/:id/view

Register a unique view for an event.

- **Request Body**:
  ```json
  { "user_id": 1 }
  ```
- **Response**: `200 OK`
- **Notes**: Increments `unique_views` on the event. Duplicate views by the same user are ignored via the `event_views` table.

### POST /api/v1/events/:id/favorite

Toggle event favorite status.

- **Request Body**:
  ```json
  { "user_id": 1, "is_favorite": true }
  ```
- **Response**: `200 OK`

### POST /api/v1/events/:id/favorite_group

Toggle a merchandise group favorite within an event.

- **Request Body**:
  ```json
  { "user_id": 1, "group_name": "Photos", "is_favorite": true }
  ```
- **Response**: `200 OK`

### GET /api/v1/events/:id/my-role

Report the caller's standing on an event (any active user; not gated by
`event.member.manage`). Used to pre-gate Add Merch and member-management UI.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
  ```json
  {
    "role": "creator",
    "globalOverride": true,
    "canCreateMerch": true,
    "canEditGroup": true,
    "canManageEditors": true,
    "canTransferCreator": true
  }
  ```
- **Notes**:
  - `canManageEditors` is the exact `event.member.manage` RBAC decision (#442).
  - `canTransferCreator` is true only when the caller is the current
    `events.creator_id` (ownership; not a permission).

### GET /api/v1/events/:id/members

List event-scoped role assignments (creator + editors).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
  ```json
  {
    "members": [
      { "userId": 1, "role": "creator", "username": "alice" },
      { "userId": 2, "role": "editor", "username": "bob" }
    ]
  }
  ```
- **Permissions**: Event creator or editor (`event.member.manage`), or admin
  superuser bypass. Global moderators use the admin path instead (#432 / #442).

### POST /api/v1/events/:id/members/:target_id

Assign the event-scoped `editor` role (idempotent).

- **Query Parameters**: `user_id` (required) — caller.
- **Response**: `200 OK`
- **Permissions**: Same as list members (`event.member.manage`).

### DELETE /api/v1/events/:id/members/:target_id

Revoke the event-scoped `editor` role (idempotent). Never removes the event
`creator` role.

- **Query Parameters**: `user_id` (required) — caller.
- **Response**: `200 OK`
- **Permissions**: Same as list members (`event.member.manage`).

### PUT /api/v1/events/:id/creator

Self-service transfer of event ownership (`events.creator_id` + event-scoped
`creator` role). Does **not** auto-promote the previous creator to `editor`
(#442). Staff use `PUT /admin/events/:id/creator` instead (#432).

- **Query Parameters**: `user_id` (required) — must be the **current** creator.
- **Request Body**:
  ```json
  { "newCreatorId": 9 }
  ```
- **Response**: `200 OK`
- **Errors**: `403` if caller is not the current creator; `400` if already the
  creator or target is banned; `404` if event or target user missing.

### GET /api/v1/events/:id/groups/:group_name/my-role

Report the caller's standing on a single item group (any active user; not gated
by `group.member.manage`). Used to pre-gate Manage Group Members UI (#443).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
  ```json
  {
    "role": "creator",
    "globalOverride": false,
    "canEditGroup": true,
    "canManageEditors": true,
    "canTransferCreator": true
  }
  ```
- **Notes**:
  - `canManageEditors` is the exact `group.member.manage` RBAC decision.
  - `canTransferCreator` is true only when the caller is the current
    `merchandise_groups.created_by` (ownership; not a permission).
  - `canEditGroup` is true for ownership, event-scoped `group.edit`, or
    group-scoped `group.edit`.
- **Errors**: `404` if the group does not exist.

### GET /api/v1/events/:id/groups/:group_name/members

List group-scoped role assignments (creator + editors) for an item group (#443).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
  ```json
  {
    "members": [
      { "userId": 1, "role": "creator", "username": "alice" },
      { "userId": 2, "role": "editor", "username": "bob" }
    ]
  }
  ```
- **Permissions**: Group creator or editor (`group.member.manage`), or admin
  superuser bypass. No `*.any` for moderators.
- **Errors**: `404` if the group is missing (before 403).

### POST /api/v1/events/:id/groups/:group_name/members/:target_id

Assign the group-scoped `editor` role (idempotent) (#443).

- **Query Parameters**: `user_id` (required) — caller.
- **Response**: `200 OK`
- **Permissions**: Same as list group members (`group.member.manage`).

### DELETE /api/v1/events/:id/groups/:group_name/members/:target_id

Revoke the group-scoped `editor` role (idempotent). Never removes the group
`creator` role (#443).

- **Query Parameters**: `user_id` (required) — caller.
- **Response**: `200 OK`
- **Permissions**: Same as list group members (`group.member.manage`).

### PUT /api/v1/events/:id/groups/:group_name/creator

Self-service transfer of group ownership (`merchandise_groups.created_by` +
group-scoped `creator` role). Does **not** auto-promote the previous creator to
`editor` (#443). Staff use `PUT /admin/events/:id/groups/:name/creator` instead
(#432).

- **Query Parameters**: `user_id` (required) — must be the **current** group
  creator (`created_by`).
- **Request Body**:
  ```json
  { "newCreatorId": 9 }
  ```
- **Response**: `200 OK`
- **Errors**: `403` if caller is not the current creator; `400` if already the
  creator or target is banned; `404` if group or target user missing.

### GET /api/v1/user/:id/favorite_groups

List a user's favorite merchandise groups.

- **Response**: `200 OK`
  ```json
  [
    { "event_id": 1, "group_name": "Photos", "created_at": "2025-07-01T00:00:00Z" }
  ]
  ```

---

## 3. Merchandise

### GET /api/v1/events/:id/merch

List merchandise for an event. Returns published items plus the requesting user's own drafts. Excludes soft-deleted items for every viewer (including creator/moderator and HAVE holders) — ADR 0011 / #468. Soft-deleted rows remain visible only via holder inventory (`GET /api/v1/user/:id/inventory`) and historical match detail.

- **Query Parameters**:
  | Param     | Type | Description                                 |
  |-----------|------|---------------------------------------------|
  | `user_id` | int  | Optional. Include this user's draft merch.  |
- **Response**: `200 OK`
  ```json
  [
    {
      "id": 101,
      "event_id": 1,
      "name": "Photo 01",
      "photo_url": "https://...",
      "group_name": "Photos",
      "sort_order": 0,
      "status": "published",
      "is_deleted": false,
      "trade_enabled": true,
      "creator_id": 1
    }
  ]
  ```

### POST /api/v1/events/:id/merch

Create merchandise for an event.

- **Request Body**:
  ```json
  {
    "name": "Photo 03",
    "photo_url": "https://...",       // optional
    "group_name": "Photos",           // optional
    "creator_id": 1,                  // optional
    "status": "draft"                 // optional, defaults to "published"
  }
  ```
- **Response**: `201 Created`
  ```json
  { "id": 103, "name": "Photo 03", "status": "draft" }
  ```

### POST /api/v1/events/:id/merch/:merch_id/publish

Publish a draft merchandise item.

- **Request Body**:
  ```json
  { "user_id": 1 }
  ```
- **Response**: `200 OK`
- **Permissions**: Merch creator, admin, or moderator only.

### DELETE /api/v1/events/:id/merch/:merch_id

Delete a merchandise item. Always soft-deletes (`is_deleted = TRUE`, `trade_enabled = FALSE`) and cancels active matches that reference the item (ADR 0008). Soft-deleted rows are omitted from catalog lists (ADR 0011).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`

### POST /api/v1/events/:id/merch/sort

Update the display sort order for merchandise in an event.

- **Request Body**:
  ```json
  {
    "event_id": 1,
    "sort_orders": { "101": 0, "102": 1, "103": 2 }
  }
  ```
- **Response**: `200 OK`

---

## 4. Inventory

### POST /api/v1/user/inventory

Upsert a user's inventory entry. Creates or updates the record based on the unique `(user_id, merch_id, status)` constraint.

`status` is one of `HAVE` / `WANT` / `TRADE`. **TRADE** and **WANT** participate in matching and trade capacity; **HAVE** is optional ownership bookkeeping and does not gate offer/accept. Full semantics: [architecture §06](../explanation/architecture/06-runtime.md#inventory-status-semantics).

- **Request Body**:
  ```json
  {
    "user_id": 1,
    "merch_id": 101,
    "status": "HAVE",                // "HAVE", "WANT", or "TRADE"
    "quantity": 2
  }
  ```
- **Response**: `200 OK`

### GET /api/v1/user/:id/inventory

Get a user's full inventory.

- **Response**: `200 OK`
  ```json
  [
    { "id": 1, "user_id": 1, "merch_id": 101, "status": "HAVE", "quantity": 2, "updated_at": "..." }
  ]
  ```

---

## 5. Matches

### GET /api/v1/matches/user/:id

List all matches for a user (where the user is `user1_id` or `user2_id`).

- **Response**: `200 OK`
  ```json
  [
    {
      "id": 500,
      "user1_id": 1,
      "user2_id": 2,
      "status": "PENDING",
      "created_at": "2025-07-01T00:00:00Z"
    }
  ]
  ```

### POST /api/v1/matches/:id/status

Update the status of a match.

- **Request Body**:
  ```json
  { "status": "ACCEPTED" }
  ```
- **Allowed values**: `ACCEPTED`, `REJECTED`, `COMPLETED`
- **Response**: `200 OK`

### POST /api/v1/matches/:id/apply-inventory

Apply this user's inventory deltas for a **COMPLETED** match. Each participant
applies independently; a second apply for the same user returns `409 Conflict`.

Per absolute leg `(giver_user_id, merch_id, quantity)`
([ADR 0009](../explanation/adr/0009-apply-inventory-decrements-giver-have.md),
[ADR 0014](../explanation/adr/0014-fail-closed-inventory-apply.md)):

| Party | Default | `skipHaveDecrement: true` |
|-------|---------|---------------------------|
| Giver | `TRADE −qty` (**fail-closed** if insufficient), `HAVE −qty` (**clamp ≥ 0**) | `TRADE −qty` only |
| Receiver | `HAVE +qty` | same (flag ignored) |

HAVE is optional bookkeeping: short/missing HAVE never fails apply. TRADE is
the trade pool and must cover `qty`. See
[inventory status semantics](../explanation/architecture/06-runtime.md#inventory-status-semantics).

- **Request Body**:
  ```json
  {
    "userId": 1,
    "skipHaveDecrement": false
  }
  ```
  - `userId` (required): applying user (must be a match participant).
  - `skipHaveDecrement` (optional, default `false`): when `true`, do not
    decrement the giver's HAVE (legacy).
- **Response**: `200 OK`
- **Errors**: `400` if match is not `COMPLETED`, or insufficient **TRADE** for
  a give leg; `403` if not a participant; `404` if match missing; `409` if
  this user already applied.
- **Concurrency / client retry** (#492): check, deltas, and the per-user
  applied flag run in one transaction under a row lock, with a conditional
  mark (`WHERE applied_at IS NULL`). Concurrent applies for the same user
  yield exactly one `200` and one `409`; inventory changes once.
  - **`409 Conflict`**: treat as already applied — refresh match /
    inventory UI; **do not** retry apply expecting further inventory
    mutation.
  - **Network timeout / no response**: safe to retry once. At most one
    attempt applies deltas; further successful attempts are impossible
    (they return `409`).

---

## 6. Messages

### GET /api/v1/matches/:id/messages

List all messages in a match conversation (#491).

- **Query Parameters**:
  | Param     | Type | Description                                      |
  |-----------|------|--------------------------------------------------|
  | `user_id` | int  | Required. Must be an active match participant.   |
- **Response**: `200 OK`
  ```json
  [
    {
      "id": 1,
      "match_id": 500,
      "sender_id": 1,
      "content": "Hello!",
      "created_at": "2025-07-01T00:00:00Z",
      "message_type": "TEXT",
      "latitude": null,
      "longitude": null
    }
  ]
  ```
- **Errors**: `400` missing `user_id`; `403` not a participant / banned;
  `404` match not found.

### POST /api/v1/matches/:id/messages

Send a message in a match conversation (#491).

- **Request Body**:
  ```json
  {
    "match_id": 500,
    "sender_id": 1,
    "content": "Let's meet at the north gate.",
    "message_type": "LOCATION",       // optional, defaults to "TEXT"; client may send TEXT or LOCATION only
    "latitude": 35.6762,              // optional
    "longitude": 139.6503             // optional
  }
  ```
- **Authorization**: `sender_id` must be an active match participant. Content
  max length 2000 characters. `SYSTEM` type is server-only.
- **Response**: `200 OK` — the created message.
- **Errors**: `400` invalid type/length; `403` not a participant / banned;
  `404` match not found.

---

## 7. Admin

All admin endpoints require the `user_id` query parameter, and the requesting user must have the `admin` or `moderator` role (unless otherwise noted).

### GET /api/v1/admin/merch

List all merchandise (published + drafts). Soft-deleted rows are excluded (same live-only catalog rule as event list; ADR 0011).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Permissions**: Admin or moderator (`merch.delete.any`).
- **Response**: `200 OK` — Array of merchandise objects.

### GET /api/v1/admin/matches

List all matches.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Permissions**: Admin or moderator (`match.delete`).
- **Response**: `200 OK` — Array of match objects.

### DELETE /api/v1/admin/events/:id

Delete an event.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
- **Permissions**: Admin or moderator only.

### DELETE /api/v1/admin/merch/:id

Delete merchandise. Always soft-deletes (`is_deleted = TRUE`, `trade_enabled = FALSE`) and cancels active matches that reference the item (ADR 0008). Soft-deleted rows are omitted from catalog lists (ADR 0011).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
- **Permissions**: Admin or moderator only.

### DELETE /api/v1/admin/matches/:id

Delete a match.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
- **Permissions**: Admin or moderator only.

### GET /api/v1/admin/users/:id

Get detailed user information (includes sensitive fields such as `device_token`).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
  ```json
  {
    "id": 1,
    "username": "user123",
    "role": "user",
    "is_banned": false,
    "ban_reason": null,
    "banned_until": null,
    "created_at": "2025-07-01T00:00:00Z"
  }
  ```
- **Permissions**: Admin or moderator only (`user.read`).

### POST /api/v1/admin/users/:id/ban

Ban a user.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Request Body**:
  ```json
  {
    "reason": "Spam",                  // optional
    "banned_until": "2025-12-31T00:00:00Z"  // optional, NULL = permanent
  }
  ```
- **Response**: `200 OK`
- **Permissions**: Admin or moderator only.

### POST /api/v1/admin/users/:id/unban

Unban a user.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
- **Permissions**: Admin or moderator only.

### POST /api/v1/admin/users/:id/role

Update a user's role.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Request Body**:
  ```json
  { "role": "moderator" }
  ```
- **Allowed values**: `user`, `moderator`, `admin`
- **Response**: `200 OK`
- **Permissions**: **Admin only** (moderators cannot change roles).

### PUT /api/v1/admin/events/:id/creator

Transfer event ownership (`events.creator_id` + event-scoped `creator` role).
Does **not** auto-promote the previous creator to `editor` (#432).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Request Body**:
  ```json
  { "newCreatorId": 42 }
  ```
- **Response**: `200 OK`
- **Errors**: `400` if already the creator or target is banned; `404` if event or target user missing; `403` if caller lacks permission.
- **Permissions**: Admin or moderator (`event.creator.transfer`).

### PUT /api/v1/admin/events/:id/groups/:group_name/creator

Transfer item-group ownership (`merchandise_groups.created_by` + group-scoped
`creator` role) in one transaction (#432 / #443). Does **not** auto-promote the
previous creator to `editor`.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Request Body**:
  ```json
  { "newCreatorId": 42 }
  ```
- **Response**: `200 OK`
- **Permissions**: Admin or moderator (`group.creator.transfer`).

### GET /api/v1/admin/events/:id/members

List event-scoped role assignments (creator + editors) via the admin path (#432).
Separate from the public `GET /events/:id/members` (creator/editor + admin
bypass) so global moderators can inspect membership without holding
`event.member.manage`.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
  ```json
  {
    "members": [
      { "userId": 1, "role": "creator", "username": "alice" },
      { "userId": 2, "role": "editor", "username": "bob" }
    ]
  }
  ```
- **Permissions**: Admin or moderator (`event.member.manage.any`).

### POST /api/v1/admin/events/:id/members/:target_id

Assign the event-scoped `editor` role (idempotent) (#432).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
- **Permissions**: Admin or moderator (`event.member.manage.any`).

### DELETE /api/v1/admin/events/:id/members/:target_id

Revoke the event-scoped `editor` role (idempotent). Never removes the
event `creator` role (#432).

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Response**: `200 OK`
- **Permissions**: Admin or moderator (`event.member.manage.any`).

### GET /api/v1/admin/groups

List all item groups for the moderation dashboard.

- **Query Parameters**:
  | Param     | Type | Description                         |
  |-----------|------|-------------------------------------|
  | `user_id` | int  | Required. The requesting user's ID. |
- **Permissions**: Admin or moderator (`group.delete`).
- **Response**: `200 OK` — Array of objects:
  ```json
  [
    {
      "eventId": 1,
      "eventName": "Live 2025",
      "groupName": "pins-key",
      "displayName": "Enamel Pins",
      "creatorId": 3,
      "creatorUsername": "alice",
      "itemCount": 12
    }
  ]
  ```
- `displayName`, `creatorId`, and `creatorUsername` are omitted when unset.

---

## 8. Search

### GET /api/v1/search

Search across events and merchandise by name. Excludes soft-deleted and draft items.

- **Query Parameters**:
  | Param | Type   | Description         |
  |-------|--------|---------------------|
  | `q`   | string | Required. Search term. |
- **Response**: `200 OK`
  ```json
  {
    "events": [
      { "id": 1, "name": "Yukari Live 2025" }
    ],
    "merchandise": [
      { "id": 101, "name": "Photo 01", "event_id": 1 }
    ]
  }
  ```

---

## 9. System

### GET /api/v1/system/status

Backend health check.

- **Response**: `200 OK`
  ```json
  { "status": "ok" }
  ```

---

## Permission Summary

| Role        | Capabilities                                                                     |
|-------------|----------------------------------------------------------------------------------|
| `user`      | Create events/merch, manage own inventory, trade, message.                       |
| `moderator` | All user abilities + delete any event/merch/match via admin endpoints.           |
| `admin`     | All moderator abilities + manage user roles and bans.                            |

Banned users receive `403 Forbidden` on login and are blocked from creating events.
