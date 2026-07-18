# UI/UX Specifications

## Core Philosophy

**"Inventory is Contextual"**: Users manage collections per event, not globally. The primary entry point is the **Event List** (Items tab).

## Navigation Structure

### Bottom Navigation Bar (`BottomNavBar`)

| Tab | JA label | Icon | Screen | Description |
|-----|----------|------|--------|-------------|
| Items | アイテム | `event_outlined` | `HomeScreen` | Event list, search, favorites |
| Matches | マッチ | `swap_horiz_outlined` | `TradeListScreen` | Trade matches with badge count |
| Profile | プロフィール | `person_outlined` | `ProfileScreen` | User profile, UUID, settings |
| Admin | 管理 | `admin_panel_settings_outlined` | `AdminDashboardScreen` | Admin/moderator only, conditional |

> **Terminology:** the first tab is labeled **Items / アイテム** in the UI but
> is the `HomeScreen` (event list) in code — there is no tab labeled "Home".

### Screen Stack

```
BottomNavBar
├── Items Tab
│   ├── HomeScreen (event list)
│   └── EventDetailScreen (merchandise per event)
│       └── AddMerchScreen (new item form)
├── Matches Tab
│   ├── TradeListScreen (match list)
│   └── ChatScreen (messaging per match)
│       └── MapPickerScreen (location selection)
├── Profile Tab
│   └── ProfileScreen
└── Admin Tab (conditional)
    └── AdminDashboardScreen
```

## Screen Details

### LoginScreen

- App branding (logo, title "ymatch", tagline)
- Backend error banner (Japanese) with retry when backend unreachable
- Loading spinner with "Logging in..." text
- **Primary Actions**:
  - "Start as New User" — creates guest session
  - "Restore Existing Account" — shows UUID input form
- **How-to pointer (#336)**: in the default new-user state, a hint line
  (`howToHint`) + a long down arrow + a `VirtualProfileTabBar` (a dashed
  "virtual" Profile tab) rendered in the bottom-nav area — the same area the
  real nav bar occupies after login. Only the Profile tab is shown (Items /
  Matches hidden), in its real rightmost position. Tapping it does **not**
  open the guide; it shows the `howToPreviewTabHint` snackbar ("Available
  after login" / ログイン後に使用できます). Hidden during backend error /
  loading / restore.

### HomeScreen (Items Tab)

- **AppBar**: Search bar (events/groups), **help (?) icon** (`HowToTradeIconButton`, #336 — opens the How to Trade guide sheet; emphasized on first login), refresh button, sort popup menu (Newest / Most Popular / Alphabetical)
- **Favorite Shortcuts**: Horizontal scrollable row of `ActionChip` widgets for favorited events and groups
- **Filter Bar**: `SegmentedButton` — All Events, Favorites, My Items
- **Event List**: `ListView.builder` of event cards with:
  - Event icon, name, owner edit icon
  - DRAFT badge (orange) for unpublished events
  - Participant count, view count, created date
  - Favorite star toggle
- **FAB**: "New Event" — opens name dialog
- **Long-press (owner only)**: Bottom sheet with "Edit Name" / "Delete"
- **Empty state**: Centered icon + "Create Event" button

### EventDetailScreen

- **AppBar**: Search bar (items), **help (?) icon** (`HowToTradeIconButton`, #336 — opens the How to Trade guide sheet; emphasized on first login), refresh, popup menus:
  - Inventory display: Just HAVE / WANT & TRADE / All
  - View mode: Detailed / Grid / Compact List
  - Overflow: Want All Missing / Export inventory
- **TabBar**: Dynamic scrollable tabs per merchandise group, each with favorite star
- **Filter Bar**: `SegmentedButton` — All, HAVE, WANT, Missing (with count badge)
- **Content**: `TabBarView` with per-group content in selected view mode:
  - **Detailed View**: `ReorderableListView` with image, name, owner icon, stepper counters
  - **Grid View**: 3-column `GridView` with image, name, compact +/- counters
  - **Compact List**: `ListView` with thumbnail, name, inline counters
- **Bottom-left controls** (icon-only, safe-area aware):
  - Group info (everyone) — toggles description panel (#128)
  - Edit Group — group creator or `canEditGroup` (#425)
  - Manage Members — `canManageEditors` / `canTransferCreator` (#442); moved off AppBar (#464)
- **FAB**: "Add Merch" — opens `AddMerchScreen`
- **Long-press (owner only)**: Bottom sheet with "Edit Name" / "Delete"

### AddMerchScreen

- **Group Selection**: Horizontal scrollable `FilterChip` widgets per group + "New Group" chip
- **Item Name**: Auto-focused `TextField`
- **Image Picker**: 80x80 preview, "Choose Image" / "Change Image" / "Remove"
- **Submit**: "Add Item" button with loading spinner
- **Preview**: Existing items in selected group (thumbnail + name)

### TradeListScreen (Matches Tab)

- **AppBar**: Title "Trades"
- **TabBar**: 5 tabs with badge counts:
  - **Match**: Pending matches — Reject / Make Offer buttons
  - **Offer Out**: Sent offers — Cancel / "Waiting..." text
  - **Offer In**: Received offers — Reject / Accept buttons
  - **Active**: Accepted trades — Mark Complete button
  - **Done**: Completed trades — "Update Inventory" button
- **Match Card**: User avatar, username, status chip, chat icon, selected items (Give/Receive), potential items

### ChatScreen

- **Message List**: Bubbles aligned right (own) / left (other)
- **Link Detection**: Clickable URL cards with map/link icons
- **Input Bar**: Location pin button, text field, send button

### MapPickerScreen

- Full-screen `FlutterMap` (OpenStreetMap tiles)
- Tap to place marker
- Place/address search (OSM Nominatim) — selecting a result moves pin + camera
- "My location" control — device GPS (permission-gated); snackbar on denial/failure
- "Confirm" button returns `LatLng`
- Default center: Tokyo when GPS is unavailable

### ProfileScreen

- **Profile Card**: Avatar, editable username (inline), UUID with copy button, warning text
- **Instructions Card**: 3-step "How to Trade" guide
- **Logout Button**: Red themed
- **Revision Info**: Frontend/backend git hashes

### AdminDashboardScreen

- **Access Denied**: Fallback for non-admin users
- **TabBar**: 6 tabs:
  - **System**: Backend revision, memory/CPU/uptime/OS
  - **Users**: User list with role, ban status, popup menu (Ban/Unban/Set Role)
  - **Events**: Event list with DRAFT badge, delete button
  - **Items**: Merch list with photo, delete button
  - **Matches**: Match list with status, delete button
  - **Debug**: Version info, generate test data, open guest session

## Permissions

| Role | UI Access |
|------|-----------|
| `user` | All standard screens, own items management |
| `moderator` | + Admin tab (read-only for some) |
| `admin` | + Full admin capabilities (ban, delete, role changes) |

Banned users see error banners and are blocked from write operations.
