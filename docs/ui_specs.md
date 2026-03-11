# UI/UX Specifications

## Core Philosophy
**"Inventory is Contextual"**: Users rarely manage a global "inventory"; they manage their collection *per event*. Therefore, the primary entry point for inventory management should be the **Event List**.

## Navigation Structure (Revised)
### 1. Bottom Navigation Bar
- **Tab 1: Events (Inventory)**
    - *Primary View*: List of Event Groups.
    - *Action*: User selects an Event to view its Merch/Inventory.
    - *Context*: This replaces the standalone "Profile/Inventory" tab for management.
- **Tab 2: Matches (Trade)**
    - *Primary View*: List of active/pending matches.
    - *Action*: Chat, Accept/Reject trades.
- **Tab 3: Profile (Settings)**
    - *Primary View*: User details (UUID), Global Stats, App Settings.
    - *Note*: Detailed item management moves to Tab 1.

## Screen Details

### Event List Screen (Tab 1)
- Displays all available Event Groups.
- **FAB (Floating Action Button)**: "Create New Event".
- **List Item**:
    - Event Name.
    - Creator Name.
    - *Visual Indicator*: "You have 3 items, Want 2 items" (Summary of user's status for this event).

### Event Detail / Inventory Screen
- Accessed by tapping an Event in Tab 1.
- **Header**: Event Name.
- **Content**: Grid or List of Merchandise.
- **Item Card**:
    - Photo & Name.
    - **Controls**:
        - **HAVE**: Counter `[-] 2 [+]` (Green highlight if > 0).
        - **WANT**: Toggle/Counter `[-] 1 [+]` (Pink highlight if > 0).
    - *Goal*: User can rapidly tap "+" on items they just bought (blind bag opening scenario).

### Match Detail Screen
- Shows the proposed trade:
    - **You Give**: Item A (Photo/Name).
    - **You Get**: Item B (Photo/Name).
- **Actions**: [Accept], [Reject], [Chat].
