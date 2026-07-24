import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';

/// Colored status pill for a match lifecycle state.
class MatchStatusChip extends StatelessWidget {
  const MatchStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    late final Color color;
    late final String label;
    switch (status) {
      case 'PENDING':
        color = Colors.orange;
        label = l10n.statusPending;
      case 'OFFERED':
        color = Colors.blue;
        label = l10n.statusOffered;
      case 'ACCEPTED':
        color = Colors.green;
        label = l10n.statusAccepted;
      case 'COMPLETED':
        color = Colors.grey;
        label = l10n.statusCompleted;
      case 'CANCELLED':
        color = Colors.brown;
        label = l10n.statusCancelled;
      default:
        color = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// ADR 0012: chip under the status when this pair+group was rematched.
class PriorHistoryAnnotation extends StatelessWidget {
  const PriorHistoryAnnotation({super.key, required this.match});

  final TradeMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final base = switch (match.lastTerminalStatus) {
      'REJECTED' => l10n.matchRejectedBefore,
      'CANCELLED' => l10n.matchCancelledBefore,
      _ => match.lastTerminalStatus,
    };
    final label = match.rematchCount > 1
        ? '$base · ${l10n.matchRematchCount(match.rematchCount)}'
        : base;
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.deepOrange[700],
      ),
    );
  }
}
