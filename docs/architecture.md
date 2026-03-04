# System Architecture & Actors

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

```text
+-------------+       +--------------+       +----------+
|   Flutter   | <---> |  Rust (Axum) | <---> | Postgres |
|   (Mobile)  |       |  (REST API)  |       |   (DB)   |
+-------------+       +--------------+       +----------+
```
