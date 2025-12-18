# Requirements Specification

## 1. Introduction
ymatch is a merchandise trading platform designed to facilitate physical exchanges of event merchandise between users.

## 2. functional Requirements

### 2.1 Event Management
- **FR-01**: Users can create arbitrary "Event Groups" (e.g., "Yukari live 2025 winter").
- **FR-02**: Event Groups must track metadata (Name, Date, etc.).
- **FR-03**: Users can link "Merchandise Information" to Event Groups.
- **FR-04**: Merchandise Information includes Name and Photos (multiple photos supported, though MVP may start with one).

### 2.2 Inventory Management
- **FR-05**: Users can browse Event Groups and view associated Merchandise.
- **FR-06**: Users can manage their personal inventory for specific merchandise items.
- **FR-07**: Inventory tracking includes:
    - **Quantity**: How many instances of the item the user owns.
    - **Status**: Whether the item is "HAVE" (Surplus/Tradeable) or "WANT" (Missing/Desired).

### 2.3 Trade Matching
- **FR-08**: Users can advertise trade requests based on their Surplus (HAVE) and Missing (WANT) items.
- **FR-09**: The system performs matching algorithms to identify users with compatible needs (User A has X and wants Y; User B has Y and wants X).

### 2.4 Communication & Exchange
- **FR-10**: The platform provides a messaging system for matched users.
- **FR-11**: Users can share location information to facilitate physical exchange sessions.

## 3. Non-Functional Requirements
- **NFR-01**: Platform support: Android and iOS (via Flutter).
- **NFR-02**: Backend: Central server (Rust) capable of local and cloud deployment.
- **NFR-03**: Performance: Support real-time or near-real-time updates for high-traffic event days.
