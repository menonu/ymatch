# Use Cases

## Actors

- **General User**: A fan attending an event or trading merch.
- **System**: The backend matching engine and server.

## UC-01: Manage Event Inventory

**Goal**: User tracks what they have and what they need for a specific event.
**Trigger**: User attends an event or buys merchandise.
**Flow**:

1. User navigates to the **Event Tab**.
2. User selects a specific Event Group (e.g., "Yukari Live 2025").
3. System displays the list of Merchandise for that event.
4. User selects a specific item (e.g., "Photo Set A").
5. User adjusts their status:
   - **HAVE**: Sets count (e.g., "I have 3 duplicates").
   - **WANT**: Marks as desired (e.g., "I need 1").
6. System updates the user's inventory profile.

## UC-02: Create Trade Request

**Goal**: User wants to complete their collection by trading duplicates.
**Pre-condition**: User has defined at least one HAVE and one WANT item (or just HAVE if selling/giving away? _Assumption: Trading relies on pairs_).
**Flow**:

1. User implicitly "advertises" by updating their inventory statuses (UC-01).
2. (Optional) User sets specific trade preferences (e.g., "Will trade Photo A for Photo B OR C").

## UC-03: Find Matches

**Goal**: System identifies trading partners.
**Flow**:

1. System analyzes the global pool of HAVE/WANT lists.
2. System identifies User A (Has X, Wants Y) and User B (Has Y, Wants X).
3. System notifies both users of a "Potential Match".

## UC-04: Execute Trade

**Goal**: Users physically exchange items.
**Flow**:

1. Users view the Match Details.
2. Users use the in-app **Messaging** feature to coordinate a meeting spot.
3. Users share Location (optional).
4. Users meet and exchange items.
5. Users mark the trade as "COMPLETED" in the app.
6. System updates their inventory (decrements HAVEs, removes WANTs).

## UC-05: Create Event (User Generated)

**Goal**: User adds a missing event to the platform.
**Flow**:

1. User navigates to "Create Event".
2. User enters Event Name.
3. User adds Merchandise items (Names, Photos).
4. System publishes the Event Group.
