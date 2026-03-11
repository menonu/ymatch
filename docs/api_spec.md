# API Specification - ymatch

Base URL: `/api/v1`

## 1. Authentication

### POST /auth/signup
Create a new user.
- **Request**:
  ```json
  {
    "username": "user123",
    "password": "securepassword",
    "device_token": "fcm_token_..." // Optional, for notifications
  }
  ```
- **Response**: `201 Created`
  ```json
  { "token": "jwt_token", "user_id": 1 }
  ```

### POST /auth/login
- **Request**: `{ "username": "...", "password": "..." }`
- **Response**: `200 OK` `{ "token": "..." }`

---

## 2. Events & Merchandise

### GET /events
List all event groups.
- **Response**: `200 OK`
  ```json
  [
    { "id": 1, "name": "Yukari Live 2025", "created_at": "2025-12-01T..." }
  ]
  ```

### POST /events
Create a new event.
- **Request**: `{ "name": "..." }`

### GET /events/:id/merch
List merchandise for an event.
- **Response**: `200 OK`
  ```json
  [
    { "id": 101, "name": "Photo 01", "photo_url": "..." },
    { "id": 102, "name": "Photo 02", "photo_url": "..." }
  ]
  ```

### POST /events/:id/merch
Add merchandise to an event.
- **Request**: `{ "name": "Photo 03", "photo_url": "..." }`

---

## 3. User Inventory

### GET /user/inventory
Get current user's inventory status.
- **Response**: `200 OK`
  ```json
  [
    { "merch_id": 101, "status": "HAVE" },
    { "merch_id": 102, "status": "WANT" }
  ]
  ```

### POST /user/inventory
Update inventory status.
- **Request**:
  ```json
  {
    "merch_id": 101,
    "status": "HAVE" // Enum: HAVE, WANT, NONE
  }
  ```

---

## 4. Matching & Trades

### GET /matches
Get list of matches found for the user.
- **Response**: `200 OK`
  ```json
  [
    {
      "match_id": 500,
      "partner_user": { "id": 2, "username": "trader_b" },
      "give": { "id": 101, "name": "Photo 01" },
      "get": { "id": 102, "name": "Photo 02" },
      "status": "PENDING"
    }
  ]
  ```

### POST /matches/trigger
Manually trigger matching algorithm (Dev/Debug).
- **Response**: `200 OK` `{ "new_matches": 2 }`

---

## 5. Messaging

### GET /matches/:id/messages
Get chat history for a match.
- **Response**: `200 OK`
  ```json
  [
    { "id": 1, "sender_id": 1, "content": "Hello!", "created_at": "..." }
  ]
  ```

### POST /matches/:id/messages
Send a message.
- **Request**: `{ "content": "Let's meet at the north gate." }`
