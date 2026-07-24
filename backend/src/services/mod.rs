//! Application services — cross-cutting business logic that does not belong
//! inside a single handler or a single repository.
//!
//! Phase 2 of #163 introduces [`PermissionPolicy`], which centralizes the
//! `verify + check ban + check role + check ownership` chain that was
//! previously duplicated across 5+ handlers. Multi-step domain transactions
//! live here too ([`match_lifecycle`], [`group`]).
pub mod group;
pub mod match_lifecycle;
pub mod permission_catalog;
pub mod permissions;
pub mod rbac;
