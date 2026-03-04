# Database Schema - ymatch

This schema is designed for **SQLite** (via SQLx).

```mermaid
erDiagram
    Users {
        int id PK
        string username
        string password_hash
        string device_token
        datetime created_at
    }

    Events {
        int id PK
        string name
        int creator_id FK
        datetime created_at
    }

    Merchandise {
        int id PK
        int event_id FK
        string name
        string photo_url
    }

    Inventory {
        int id PK
        int user_id FK
        int merch_id FK
        string status "HAVE | WANT"
        datetime updated_at
    }

    Matches {
        int id PK
        int user1_id FK
        int user2_id FK
        string status "PENDING | ACCEPTED | COMPLETED"
        datetime created_at
    }

    Messages {
        int id PK
        int match_id FK
        int sender_user_id FK
        string content
        datetime created_at
    }

    Users ||--o{ Events : creates
    Events ||--o{ Merchandise : contains
    Users ||--o{ Inventory : owns
    Merchandise ||--o{ Inventory : tracked_in
    Users ||--o{ Matches : part_of
    Matches ||--o{ Messages : contains
```

## SQL Definitions (Draft)

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE inventory (
    user_id INTEGER NOT NULL,
    merch_id INTEGER NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('HAVE', 'WANT')),
    PRIMARY KEY (user_id, merch_id)
);
```
