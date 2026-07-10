// Integration tests, split into per-domain modules (see #375).
// This file is the single test-binary entry; the modules below are
// subdirectories and are NOT promoted to separate test binaries.

mod admin;
mod auth_users;
mod common;
mod event_members;
mod event_views;
mod events;
mod favorites;
mod groups;
mod images;
mod match_lifecycle;
mod merch_inventory;
mod notifications;
mod rbac;
mod system;
mod trades;
