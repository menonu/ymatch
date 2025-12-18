# AGENTS.md

This document defines the Actors (Agents) within the `ymatch` merchandise trading platform system, and tracks project progress.

## 1. System Actors

### **User (Human Agent)**
The primary participant in the ecosystem.
- **Capabilities**:
    - **Create Event Groups**: Can define new events (e.g., "Yukari Live 2025").
    - **Manage Inventory**: Catalogs merchandise they physically own (HAVE) and merchandise they desire (WANT).
    - **Advertise**: Publishes existing inventory and wishlists to the matching pool.
    - **Trade**: Executes physical exchanges based on system matches.
    - **Communicate**: Uses the messaging system to coordinate meeting locations and logistics.
- **Interface**: Mobile App (Android/iOS via Flutter), Web (via Flutter Web).

## 2. Technical Stack

| Layer      | Technology               |
|------------|--------------------------|
| Backend    | Rust (Axum, SQLx)        |
| Database   | PostgreSQL (Docker)      |
| Frontend   | Flutter (Riverpod, GoRouter) |
| API        | JSON REST                |

## 3. Architecture Overview

```
+-------------+       +--------------+       +----------+
|   Flutter   | <---> |  Rust (Axum) | <---> | Postgres |
|   (Mobile)  |       |  (REST API)  |       |   (DB)   |
+-------------+       +--------------+       +----------+
```

## 4. Current Progress

### Completed Features ✅
- **Guest Authentication**: UUID-based registration-less login.
- **Event Management**: Create/List Event Groups with Merchandise.
- **Inventory System**: `quantity`, `merch_name`, `photo_url` support.
- **UI Refactor**: Event-centric Inventory (HAVE/WANT inline controls).
- **Trade Matching Engine**: `run_matching_algorithm` (DB level).
- **Bottom Navigation**: Events, Matches, Profile.

### Pending Features ⏳
- **Trade Lifecycle**: Accept/Reject/Complete buttons on Match Detail.
- **Messaging**: In-app chat for matched users.
- **Location Sharing**: Coordinate physical exchange.
- **Push Notifications**: Alert users of new matches.

## 5. Running the Project

### Prerequisites
- Docker & Docker Compose
- Rust (cargo)
- Flutter SDK

### Commands
```bash
# Start Database
docker-compose up -d

# Run Backend
cd backend
DATABASE_URL=postgres://ymatch_user:secure_dev_password@localhost:5432/ymatch cargo run --bin backend

# Run Frontend (Web)
cd frontend
flutter run -d web-server --web-port 8081
```

### API Endpoints
| Method | Endpoint                      | Description                     |
|--------|-------------------------------|---------------------------------|
| POST   | `/api/v1/auth/guest`          | Guest login/register by UUID    |
| GET    | `/api/v1/events`              | List all events                 |
| POST   | `/api/v1/events`              | Create new event                |
| GET    | `/api/v1/events/:id/merch`    | List merch for event            |
| POST   | `/api/v1/events/:id/merch`    | Add merch to event              |
| GET    | `/api/v1/user/:id/inventory`  | Get user inventory (with details)|
| POST   | `/api/v1/user/inventory`      | Update inventory item           |
| POST   | `/api/v1/matches/trigger`     | Run matching algorithm          |
| GET    | `/api/v1/matches/user/:id`    | List matches for user           |

## 6. Documentation
- [Requirements](./docs/requirements.md)
- [Use Cases](./docs/use_cases.md)
- [UI Specs](./docs/ui_specs.md)

## 7. Development Guidelines

- **Always Rebuild and Restart**: Before testing any changes, ensure the application (Backend/Frontend) is rebuilt and restarted to apply the latest code.
- **Verify Version**: Confirm that the version/build being tested reflects the most recent changes before proceeding with verification.
- **Verify Process and Port Status**: Before test, confirm that backend and frontend is working by checking process alive and port is opened (e.g., using `lsof` or `netstat`).
- **Protobuf First**: Any changes to data structures must be applied to `proto/models.proto` first, then regenerated.
