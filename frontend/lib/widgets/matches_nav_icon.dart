import 'package:flutter/material.dart';

/// Bottom-nav Matches icon with two independent affordances (#535):
///
/// - **Top-right red count** — sum of pending / offers-in / accepted matches.
/// - **Bottom-right purple chat icon** — any unread peer messages (presence
///   only; full Message(N) lives on each match card).
///
/// Presentation only; counts arrive from [notificationCountsProvider].
class MatchesNavIcon extends StatelessWidget {
  const MatchesNavIcon({
    super.key,
    required this.icon,
    required this.matchCount,
    required this.hasUnreadMessages,
  });

  final IconData icon;

  /// Lifecycle match notifications (pending + offers in + accepted).
  final int matchCount;

  /// True when the user has any unread peer chat messages.
  final bool hasUnreadMessages;

  /// Purple used for the message presence marker (distinct from red count).
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
            child: _MatchCountBadge(count: matchCount),
          ),
        if (hasUnreadMessages)
          const Positioned(
            right: -8,
            bottom: -6,
            child: _MessagePresenceBadge(),
          ),
      ],
    );
  }
}

class _MatchCountBadge extends StatelessWidget {
  const _MatchCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red,
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

/// Compact purple chat marker — not a count (nav treats messages as +1).
class _MessagePresenceBadge extends StatelessWidget {
  const _MessagePresenceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: MatchesNavIcon.messageBadgeColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: const Icon(Icons.chat_bubble, size: 8, color: Colors.white),
    );
  }
}
