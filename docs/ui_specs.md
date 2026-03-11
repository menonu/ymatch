# UI/UX Specifications

## Core Philosophy

**"Inventory is Contextual"**: Users rarely manage a global "inventory"; they manage their collection _per event_. Therefore, the primary entry point for inventory management should be the **Event List**.

## Navigation Structure (Revised)

### 1. Bottom Navigation Bar

- **Tab 1: Events (Inventory)**
  - _Primary View_: List of Event Groups.
  - _Action_: User selects an Event to view its Merch/Inventory.
  - _Context_: This replaces the standalone "Profile/Inventory" tab for management.
- **Tab 2: Matches (Trade)**
  - _Primary View_: List of active/pending matches.
  - _Action_: Chat, Accept/Reject trades.
- **Tab 3: Profile (Settings)**
  - _Primary View_: User details (UUID), Global Stats, App Settings.
  - _Note_: Detailed item management moves to Tab 1.

## Screen Details

### Event List Screen (Tab 1)

- Displays all available Event Groups.
- **FAB (Floating Action Button)**: "Create New Event".
- **List Item**:
  - Event Name.
  - Creator Name.
  - _Visual Indicator_: "You have 3 items, Want 2 items" (Summary of user's status for this event).

### Event Detail / Inventory Screen

- Accessed by tapping an Event in Tab 1.
- **Header**: Event Name.
- **Content**: Grid or List of Merchandise.
- **Item Card**:
  - Photo & Name.
  - **Controls**:
    - **HAVE**: Counter `[-] 2 [+]` (Green highlight if > 0).
    - **WANT**: Toggle/Counter `[-] 1 [+]` (Pink highlight if > 0).
  - _Goal_: User can rapidly tap "+" on items they just bought (blind bag opening scenario).

### Match Detail Screen

- Shows the proposed trade:
  - **You Give**: Item A (Photo/Name).
  - **You Get**: Item B (Photo/Name).
- **Actions**: [Accept], [Reject], [Chat].
