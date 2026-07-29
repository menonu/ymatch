import 'package:flutter/material.dart';

/// Bottom-nav Matches icon with two independent count badges (#535):
///
/// - **Top-right red** — sum of pending / offers-in / accepted matches.
/// - **Bottom-right purple** — unread peer message count (same total as
///   the API `unreadMessages` field; per-card Message(N) is separate).
///
/// Presentation only; counts arrive from [notificationCountsProvider].
class MatchesNavIcon extends StatelessWidget {
  const MatchesNavIcon({
    super.key,
    required this.icon,
    required this.matchCount,
    required this.unreadMessageCount,
  });

  final IconData icon;

  /// Lifecycle match notifications (pending + offers in + accepted).
  final int matchCount;

  /// Unread peer chat messages across active matches.
  final int unreadMessageCount;

  /// Purple used for the message count badge (distinct from red match count).
  static const Color messageBadgeColor = Color(0xFF7B1FA2); // purple.shade700

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(icon),
        if (matchCount > 0)
          Positioned(
            right: -10,
            top: -6,
            child: _CountBadge(count: matchCount, color: Colors.red),
          ),
        if (unreadMessageCount > 0)
          Positioned(
            right: -10,
            bottom: -6,
            child: _CountBadge(
              count: unreadMessageCount,
              color: messageBadgeColor,
            ),
          ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
