/// Shared E2E helpers for logging in as the RBAC-seeded privileged users.
///
/// `scripts/e2e-seed.sql` (run by `task e2e:up` and the ci-e2e workflow) seeds
/// two users with fixed uuids and matching `user_roles` rows:
///   - `e2e-bootstrap-admin`     (global/admin)
///   - `e2e-bootstrap-moderator` (global/moderator)
///
/// `POST /api/v1/auth/guest` is idempotent on uuid, so posting one of these
/// uuids returns the seeded user's id — letting an E2E test act as an admin or
/// moderator without DB access. Use [loginE2EModerator] where a test creates
/// an event/merch (moderator has `event.create` + `merch.create.any`, and the
/// event handler auto-assigns the event/creator role so the moderator can also
/// create merch as the event creator). Use [loginE2EAdmin] for admin-only
/// endpoints (ban/role-manage/admin deletes). Fresh guests are still created
/// for "regular user" scenarios (ban targets, the second side of a trade,
/// authz outsiders).
library;

import 'package:frontend/services/api_client.dart';

/// Fixed uuid of the seeded E2E admin (global/admin + users.role='admin').
const String e2eAdminUuid = 'e2e-bootstrap-admin';

/// Fixed uuid of the seeded E2E moderator (global/moderator +
/// users.role='moderator').
const String e2eModeratorUuid = 'e2e-bootstrap-moderator';

/// Log in (idempotently) as the seeded admin and return its user id.
Future<int> loginE2EAdmin(ApiClient api) async {
  final r = await api.post('/api/v1/auth/guest', {
    'uuid': e2eAdminUuid,
    'deviceToken': 'e2e-bootstrap',
  });
  return (r as Map)['id'] as int;
}

/// Log in (idempotently) as the seeded moderator and return its user id.
Future<int> loginE2EModerator(ApiClient api) async {
  final r = await api.post('/api/v1/auth/guest', {
    'uuid': e2eModeratorUuid,
    'deviceToken': 'e2e-bootstrap',
  });
  return (r as Map)['id'] as int;
}

/// Create a fresh guest user (no elevated role) for "regular user" E2E
/// scenarios. [uuid] should be unique per call to avoid collisions across
/// re-runs on the same DB.
Future<int> createE2EGuest(ApiClient api, String uuid) async {
  final r = await api.post('/api/v1/auth/guest', {
    'uuid': uuid,
    'deviceToken': 'e2e-guest',
  });
  return (r as Map)['id'] as int;
}
