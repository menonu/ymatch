/// Shared member-row DTOs used by EventsController and AdminController.
///
/// Scoped member row from event (#432) or group (#443) list-members APIs.
/// Shape is identical across scopes (`userId`, `role`, optional `username`).
class EventMemberInfo {
  const EventMemberInfo({
    required this.userId,
    required this.role,
    this.username,
  });

  final int userId;
  final String role;
  final String? username;

  factory EventMemberInfo.fromJson(Map<String, dynamic> json) =>
      EventMemberInfo(
        userId: json['userId'] as int,
        role: json['role'] as String,
        username: json['username'] as String?,
      );
}

/// Alias for group member rows (#443); same wire shape as [EventMemberInfo].
typedef GroupMemberInfo = EventMemberInfo;
