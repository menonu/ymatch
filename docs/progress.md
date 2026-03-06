# Project Progress

## Current Progress

### Completed Features ✅
- **Authentication**: Guest Login (UUID-based).
- **Core Event Management**: Create Events, add Merchandise items, grouping merchandise into categorical tabs.
- **Inventory System**: Management of quantities with `HAVE`, `WANT`, and `TRADE` states.
- **Trade Matching**: Automated backend algorithm linking `TRADE` to `WANT` strictly within identical merchandise groups.
- **Trade Lifecycle**: Accept/Reject/Complete workflow with detailed offer confirmation dialogs.
- **Messaging (Chat)**: Real-time (polling) in-app chat for matched users.
- **Location Sharing**: Native Map Picker UI allowing users to drop a pin and send formatted Google Maps links directly in chat.
- **UI Enhancements**: 
  - Complete "Clean & Minimalist" Material 3 UI overhaul.
  - Dedicated full-screen "Add Merch" flow with rapid data entry and item previews.
  - Interactive View Modes (Detailed List with Drag-and-Drop Reordering, Grid, Compact).
  - Multi-layered Filtering (All/HAVE/WANT/Missing for items, All/Fav/Owned for events).
  - Dynamic shortcut bar for favorite events and favorite groups.
- **Admin Dashboard**: Real-time system resource monitoring (CPU, RAM, Uptime), event/item/match cascading deletion.
- **Testing**:
  - Headless API Smoke Testing (`scripts/smoke_test.sh`).
  - Comprehensive UI User Journey Scenarios testing (`user_journey_test.dart`).

### In Progress / Partially Implemented ⏳
- **Global Search**: Backend API endpoint (`/api/v1/search`) and proto models (`SearchResult`) have been created, but the Frontend UI (Search bar on Home Screen) still needs to be implemented.

### Pending Features 🚧
- **Push Notifications**: Infrastructure partially exists, needs Frontend Firebase (FCM) integration and UI alerts to notify users of new matches.
- **Data Persistence Strategy**: Move from pure guest UUIDs to persistent account binding (e.g. Email/Google/Apple) for production readiness.
- **Cloud Deployment**: Prepare container orchestration for cloud environments (AWS/GCP).