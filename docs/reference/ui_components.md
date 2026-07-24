# UI Components Reference

Component identifiers for consistent communication across the team.

> **Naming note (EN ↔ JA):** the code identifier often differs from the label a
> user sees. In particular, **`HomeScreen` is the "Items" tab** (JA: アイテム) —
> the event list a user lands on after login — **not** a tab literally called
> "Home". See the [Terminology](#terminology-en--ja) table below.

## Terminology (EN ↔ JA)

User-facing labels (what appears in the UI) for screens, tabs, and key
components, in English and Japanese. The `Identifier` column is the code symbol
used throughout this document.

### Screens

| Identifier | EN UI label | JA UI label |
|------------|-------------|-------------|
| `LoginScreen` | Login (initial screen) | ログイン（初期画面） |
| `HomeScreen` | Items tab — event list | アイテムタブ — イベント一覧 |
| `EventDetailScreen` | Event detail (within Items tab) | イベント詳細（アイテムタブ内） |
| `AddMerchScreen` | Add Merch (new item form) | アイテム追加 |
| `TradeListScreen` | Matches tab — trade list | マッチタブ — 取引一覧 |
| `ChatScreen` | Chat (within a match) | チャット（マッチ内） |
| `MapPickerScreen` | Location picker (tap / search / GPS) | 位置選択（タップ / 検索 / GPS） |
| `ProfileScreen` | Profile tab | プロフィールタブ |
| `AdminDashboardScreen` | Admin tab (admin/mod only) | 管理タブ（管理者/モデレータのみ） |

### Bottom-nav tabs

| Identifier | EN label | JA label |
|------------|----------|----------|
| Items tab | Items | アイテム |
| Matches tab | Matches | マッチ |
| Profile tab | Profile | プロフィール |
| Admin tab | Admin | 管理 |

## Screens

| Identifier | File | Description |
|-----------|------|-------------|
| `LoginScreen` | `screens/login_screen.dart` | Guest registration, account restore, backend error display |
| `HomeScreen` | `screens/home_screen.dart` | Event list with search, filters, favorites, sort; long-press for rename/delete (owner) and Manage members (#483) |
| `EventDetailScreen` | `screens/event_detail_screen.dart` | Merchandise list per event with inventory management; bottom-left group info / edit group / manage group members (#128, #425, #443). Event members: Home long-press (#483) |
| `ManageEventMembersDialog` | `widgets/manage_event_members_dialog.dart` | Self-service event members dialog (list / add / remove editor / transfer); opened from Home event-card long-press (#442, #483) |
| `AddMerchScreen` | `screens/add_merch_screen.dart` | New merchandise form with group selection, image picker |
| `TradeListScreen` | `screens/trade_list_screen.dart` | Trade matches across 5 status tabs |
| `ChatScreen` | `screens/chat_screen.dart` | Messaging within a trade match |
| `MapPickerScreen` | `screens/map_picker_screen.dart` | Location selection via OpenStreetMap; tap pin, place search (Nominatim), GPS my-location (#448) |
| `ProfileScreen` | `screens/profile_screen.dart` | User profile, UUID, trading instructions |
| `AdminDashboardScreen` | `screens/admin_dashboard_screen.dart` | Admin panel with 6 tabs (System, Users, Events, Groups, Items, Matches) plus Debug in debug builds only (#499). Events/Groups support change creator + manage editors (#432). |

## Navigation

### Bottom Navigation Bar

| Identifier | File | Tabs |
|-----------|------|------|
| `BottomNavBar` | `widgets/scaffold_with_nav_bar.dart` | Items, Matches, Profile, Admin (conditional) |

### Tab Bars

| Identifier | Parent Screen | Tabs |
|-----------|---------------|------|
| `EventGroupTabBar` | `EventDetailScreen` | Dynamic tabs per merchandise group with favorite stars |
| `TradeStatusTabBar` | `TradeListScreen` | Match, Offer Out, Offer In, Active, Done (with badge counts) |
| `AdminTabBar` | `AdminDashboardScreen` | System, Users, Events, Groups, Items, Matches; Debug only when `enableDevSessionOverrides` / `kDebugMode` (#499) |

### Popup Menus

| Identifier | Parent Screen | Options |
|-----------|---------------|---------|
| `EventSortMenu` | `HomeScreen` | Newest, Most Popular, Alphabetical |
| `InventoryDisplayMenu` | `EventDetailScreen` | Just HAVE, WANT & TRADE, All |
| `ViewModeMenu` | `EventDetailScreen` | Detailed View, Grid View, Compact List |
| `EventOverflowMenu` | `EventDetailScreen` | Want All Missing |
| `GroupJumpMenu` | `EventDetailScreen` | Jump to group dropdown |
| `AdminUserMenu` | `AdminDashboardScreen` | Ban, Unban, Set Admin/Moderator/User |

### Segmented Buttons

| Identifier | Parent Screen | Segments |
|-----------|---------------|----------|
| `EventFilterBar` | `HomeScreen` | All Events, Favorites, My Items |
| `MerchFilterBar` | `EventDetailScreen` | All, Own, Wish, For Trade, Missing (#472) |

### Floating Action Buttons

| Identifier | Parent Screen | Label |
|-----------|---------------|-------|
| `NewEventFAB` | `HomeScreen` | "New Event" |
| `AddMerchFAB` | `EventDetailScreen` | "Add Merch" |

## Dialogs

| Identifier | Parent Screen | Trigger | Content |
|-----------|---------------|---------|---------|
| `NewEventDialog` | `HomeScreen` | FAB tap / empty state button | Event name TextField |
| `EditEventNameDialog` | `HomeScreen` | Bottom sheet "Edit Name" | Event name TextField |
| `DeleteEventDialog` | `HomeScreen` | Bottom sheet "Delete" | Confirmation text |
| `EditItemNameDialog` | `EventDetailScreen` | Bottom sheet "Edit Name" | Item name TextField |
| `DeleteItemDialog` | `EventDetailScreen` | Bottom sheet "Delete" | Confirmation text |
| `TradeOfferDialog` | `TradeListScreen` | "Make Offer" button | CheckboxListTile lists for GIVE/RECEIVE items |
| `NewGroupDialog` | `AddMerchScreen` | "New Group" ActionChip | Group name TextField |
| `ImageSourceDialog` | `AddMerchScreen` | Image picker tap | Gallery / Camera options |
| `AdminBanDialog` | `AdminDashboardScreen` | User "Ban" menu | Ban reason TextField |
| `AdminDeleteEventDialog` | `AdminDashboardScreen` | Delete icon | Confirmation text |
| `AdminDeleteMerchDialog` | `AdminDashboardScreen` | Delete icon | Confirmation text |
| `AdminDeleteMatchDialog` | `AdminDashboardScreen` | Delete icon | Confirmation text |
| `AdminGenerateDataDialog` | `AdminDashboardScreen` | Generate button | Confirmation text |

## Bottom Sheets

| Identifier | Parent Screen | Trigger | Content |
|-----------|---------------|---------|---------|
| `EventActionsSheet` | `HomeScreen` | Long-press event card (owner only) | "Edit Name" + "Delete" ListTiles |
| `MerchActionsSheet` | `EventDetailScreen` | Long-press merch item (owner only) | "Edit Name" + "Delete" ListTiles |

## Cards

| Identifier | Parent Screen | Description |
|-----------|---------------|-------------|
| `EventCard` | `HomeScreen` | Event icon, name, DRAFT badge, stats, favorite toggle |
| `MerchDetailedCard` | `EventDetailScreen` | Reorderable card with image, name, stepper counters |
| `MerchGridCard` | `EventDetailScreen` | 3-column grid cell with image, name, compact counters |
| `MerchCompactRow` | `EventDetailScreen` | Inline row with thumbnail, name, counters |
| `MatchCard` | `TradeListScreen` | User avatar, status chip, local match datetime (#476), item chips, action buttons |
| `ProfileCard` | `ProfileScreen` | Avatar, editable username, UUID section |
| `InstructionsCard` | `ProfileScreen` | 3-step "How to Trade" guide |
| `SystemStatusCard` | `AdminDashboardScreen` | Memory, CPU, uptime, OS info |
| `DebugCard` | `AdminDashboardScreen` | Version info, test data generation |

## List Tiles (Admin)

| Identifier | Parent Screen | Description |
|-----------|---------------|-------------|
| `AdminUserTile` | `AdminDashboardScreen` | User avatar, name, role, popup menu |
| `AdminEventTile` | `AdminDashboardScreen` | Event name, DRAFT badge, delete button |
| `AdminMerchTile` | `AdminDashboardScreen` | Photo, name, group, delete button |
| `AdminMatchTile` | `AdminDashboardScreen` | IDs, status, date, delete button |

## Form Elements

### Text Fields

| Identifier | Parent Screen | Purpose |
|-----------|---------------|---------|
| `EventNameField` | `HomeScreen` (dialog) | New/edit event name |
| `ItemNameField` | `EventDetailScreen` (dialog) | Edit item name |
| `MerchNameField` | `AddMerchScreen` | New merchandise name |
| `UUIDField` | `LoginScreen` | Restore account UUID input |
| `UsernameField` | `ProfileScreen` | Inline username editing |
| `MessageField` | `ChatScreen` | Chat message input |
| `BanReasonField` | `AdminDashboardScreen` (dialog) | Admin ban reason |
| `GroupNameField` | `AddMerchScreen` (dialog) | New group name |

### Search Bars

| Identifier | Parent Screen | Purpose |
|-----------|---------------|---------|
| `EventSearchBar` | `HomeScreen` | Search events/groups |
| `ItemSearchBar` | `EventDetailScreen` | Search items within event |

### Chips

| Identifier | Parent Screen | Purpose |
|-----------|---------------|---------|
| `FavoriteShortcutChip` | `HomeScreen` | Favorite event/group shortcuts |
| `GroupFilterChip` | `AddMerchScreen` | Group selection |
| `NewGroupChip` | `AddMerchScreen` | Create new group |
| `StatusChip` | `TradeListScreen` | Color-coded trade status badge |
| `ItemChip` | `TradeListScreen` | Trade item with quantity |

### Counters

| Identifier | Parent Screen | Description |
|-----------|---------------|-------------|
| `StepperCounter` | `EventDetailScreen` | Tap-to-increment/decrement (Detailed view) |
| `GridCounter` | `EventDetailScreen` | Compact +/- counter (Grid view) |
| `CompactCounter` | `EventDetailScreen` | Inline label+number counter (List view) |

## Buttons

| Identifier | Parent Screen | Description |
|-----------|---------------|-------------|
| `GuestLoginButton` | `LoginScreen` | "Start as New User" ElevatedButton |
| `RestoreAccountButton` | `LoginScreen` | "Restore Existing Account" OutlinedButton |
| `RestoreSubmitButton` | `LoginScreen` | "Restore Account" ElevatedButton |
| `LogoutButton` | `ProfileScreen` | "Log Out" OutlinedButton (red) |
| `WantAllMissingButton` | `EventDetailScreen` | AppBar overflow menu action |
| `MakeOfferButton` | `TradeListScreen` | Opens TradeOfferDialog |
| `AcceptOfferButton` | `TradeListScreen` | Accept trade offer |
| `RejectOfferButton` | `TradeListScreen` | Reject trade offer |
| `CancelOfferButton` | `TradeListScreen` | Cancel outgoing offer |
| `MarkCompleteButton` | `TradeListScreen` | Mark trade as completed |
| `ApplyInventoryButton` | `TradeListScreen` | Update inventory from completed trade |
| `SendLocationButton` | `ChatScreen` | Opens MapPickerScreen |
| `ConfirmLocationButton` | `MapPickerScreen` | Confirm selected location |

## Message Bubbles

| Identifier | Parent Screen | Description |
|-----------|---------------|-------------|
| `OwnMessageBubble` | `ChatScreen` | Right-aligned, primary color |
| `OtherMessageBubble` | `ChatScreen` | Left-aligned, grey background |
| `LinkCard` | `ChatScreen` | Clickable URL card with icon |

## Utility Components

| Identifier | File | Description |
|-----------|------|-------------|
| `BackendErrorBanner` | `scaffold_with_nav_bar.dart` | Red banner when backend unreachable |
| `ImageWidget` | `utils/image_helper.dart` | Resolves HTTP/relative/base64 image URLs |
| `RevisionInfo` | `profile_screen.dart` | Frontend/backend version hash display |

## Snackbars

| Identifier | Parent Screen | Message |
|-----------|---------------|---------|
| `UsernameUpdatedSnackbar` | `ProfileScreen` | "Username updated" |
| `UsernameErrorSnackbar` | `ProfileScreen` | "Failed to update username: {error}" |
| `UUIDCopiedSnackbar` | `ProfileScreen` | "Master Key copied to clipboard" |
| `WantAllMissingSnackbar` | `EventDetailScreen` | "Added N missing items to WANT" |
| `NoMissingSnackbar` | `EventDetailScreen` | "No missing items found" |
| `MerchAddedSnackbar` | `AddMerchScreen` | "Added {name} successfully." |
| `GroupRequiredSnackbar` | `AddMerchScreen` | "Please select or create an item group first." |
| `ImagePickErrorSnackbar` | `AddMerchScreen` | "Failed to pick image: {error}" |
| `MessageSendErrorSnackbar` | `ChatScreen` | "Failed to send: {error}" |
| `TradeErrorSnackbar` | `TradeListScreen` | "Error: {error}" |
| `InventoryUpdatedSnackbar` | `TradeListScreen` | "Inventory updated!" |
| `EventDeletedSnackbar` | `AdminDashboardScreen` | "Event deleted" |
| `MerchDeletedSnackbar` | `AdminDashboardScreen` | "Item deleted" |
| `MatchDeletedSnackbar` | `AdminDashboardScreen` | "Match deleted" |
| `TestDataGeneratedSnackbar` | `AdminDashboardScreen` | "Test data generated successfully!" |

## Providers (State Management)

| Identifier | Type | Used By |
|-----------|------|---------|
| `authProvider` | `StateNotifierProvider<AuthController>` | LoginScreen, ProfileScreen |
| `currentUserProvider` | `Provider<User?>` | Most screens |
| `eventsProvider` | `FutureProvider<List<Event>>` | HomeScreen, AdminDashboardScreen |
| `favoriteGroupsProvider` | `FutureProvider<List<FavoriteGroup>>` | HomeScreen, EventDetailScreen |
| `eventsControllerProvider` | `StateNotifierProvider<EventsController>` | HomeScreen, EventDetailScreen |
| `merchProvider` | `FutureProvider.family<List<Merchandise>>` | EventDetailScreen, AddMerchScreen |
| `merchControllerProvider` | `StateNotifierProvider<MerchController>` | EventDetailScreen, AddMerchScreen |
| `inventoryProvider` | `AsyncNotifierProviderFamily` | EventDetailScreen |
| `matchesProvider` | `FutureProvider.family<List<TradeMatch>>` | TradeListScreen |
| `notificationCountsProvider` | `FutureProvider.family<NotificationCounts>` | BottomNavBar, TradeListScreen |
| `adminUsersProvider` | `FutureProvider<List<User>>` | AdminDashboardScreen |
| `adminMerchProvider` | `FutureProvider<List<Merchandise>>` | AdminDashboardScreen |
| `adminMatchesProvider` | `FutureProvider<List<TradeMatch>>` | AdminDashboardScreen |
| `adminControllerProvider` | `StateNotifierProvider<AdminController>` | AdminDashboardScreen |
| `backendSystemStatusProvider` | `FutureProvider<Map>` | AdminDashboardScreen, ProfileScreen |
| `backendHealthProvider` | `FutureProvider<bool>` | BottomNavBar |
| `searchQueryProvider` | `StateProvider<String>` | HomeScreen |
| `searchProvider` | `FutureProvider<List<SearchResult>>` | HomeScreen |
| `howToHintSeenProvider` | `StateNotifierProvider<HowToHintSeenController, bool>` | HowToTradeIconButton (HomeScreen, EventDetailScreen) |

### Local Providers (defined in screen files)

| Identifier | Parent Screen | Purpose |
|-----------|---------------|---------|
| `eventSortProvider` | `HomeScreen` | Current sort mode |
| `eventFilterProvider` | `HomeScreen` | Current filter mode |
| `viewModeProvider` | `EventDetailScreen` | Detailed / Grid / List |
| `merchFilterProvider` | `EventDetailScreen` | All / HAVE / WANT / Missing |
| `inventoryDisplayModeProvider` | `EventDetailScreen` | Just HAVE / WANT & TRADE / All |
| `itemSearchQueryProvider` | `EventDetailScreen` | Item search query |
| `messagesProvider` | `ChatScreen` | Chat messages for a match |

## How-to Guide Components (#336)

The "How to Trade" guide (3 steps, l10n keys `howToTrade` / `tradeStep1–3`) is
the single source of truth in `widgets/how_to_trade.dart` and is surfaced in
three places so new users can find it without digging into the Profile tab.

| Identifier | File | EN UI label | JA UI label | Where it appears |
|------------|------|-------------|-------------|------------------|
| `HowToTradeContent` | `widgets/how_to_trade.dart` | "How to Trade" guide (title + 3 steps) | 「取引方法」ガイド（見出し＋3ステップ） | `ProfileScreen` (`InstructionsCard`), `HowToTradeSheet` |
| `showHowToTradeSheet` | `widgets/how_to_trade.dart` | Guide bottom sheet | 取引ガイド シート | Opened by `HowToTradeIconButton` |
| `HowToTradeIconButton` | `widgets/how_to_trade.dart` | AppBar help (?) icon | AppBarヘルプ（？）アイコン | `HomeScreen`, `EventDetailScreen` AppBar |
| `VirtualProfileTabBar` | `widgets/how_to_trade.dart` | Virtual Profile tab preview | 仮想プロフィールタブ | `LoginScreen` bottom-nav area |
| `LongDownArrow` | `widgets/how_to_trade.dart` | Long pointer arrow | 長い矢印ポインタ | `LoginScreen` (points at `VirtualProfileTabBar`) |
| `HowToTradeStep` | `widgets/how_to_trade.dart` | One numbered guide step | ガイドの1ステップ | Inside `HowToTradeContent` |

### Behavior notes

- **Login screen (`VirtualProfileTabBar`)**: a *pointer*, not an entry point.
  Only the Profile tab is shown (Items/Matches hidden), in its real rightmost
  position; a long arrow points down at it. Tapping it does **not** open the
  guide — it shows the `howToPreviewTabHint` snackbar ("Available after login" /
  ログイン後に使用できます). It is only rendered in the default new-user state
  (hidden during backend error / loading / restore).
- **Home & Event Detail (`HowToTradeIconButton`)**: opens `showHowToTradeSheet`.
  On a user's first login (before they open the guide) the icon is emphasized
  — primary color + a badge dot; once opened, it becomes a plain icon. The
  "seen" state persists across sessions via `howToHintSeenProvider`
  (SharedPreferences key `how_to_hint_seen`).
- **Profile (`InstructionsCard`)**: renders `HowToTradeContent` inline — the
  guide's original home, unchanged.
