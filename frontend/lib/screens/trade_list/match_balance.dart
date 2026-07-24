import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';

/// Per-side quantity totals for the current proposal legs (#297).
/// Give = legs where the viewer is the giver; Receive = legs where the
/// other party is the giver (the viewer receives).
(int give, int receive) matchLegTotals(int userId, TradeMatch match) {
  var give = 0;
  var receive = 0;
  for (final i in match.selectedItems) {
    if (i.giverUserId == userId) {
      give += i.quantity;
    } else {
      receive += i.quantity;
    }
  }
  return (give, receive);
}

bool matchIsBalanced(int userId, TradeMatch match) {
  final (give, receive) = matchLegTotals(userId, match);
  return give == receive && give > 0;
}

/// Balance summary row shown on open proposals and in the offer dialog.
class MatchBalanceIndicator extends StatelessWidget {
  const MatchBalanceIndicator({
    super.key,
    required this.give,
    required this.receive,
  });

  /// Convenience from a match + viewer id.
  factory MatchBalanceIndicator.forMatch({
    Key? key,
    required int userId,
    required TradeMatch match,
  }) {
    final (give, receive) = matchLegTotals(userId, match);
    return MatchBalanceIndicator(key: key, give: give, receive: receive);
  }

  final int give;
  final int receive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final balanced = give == receive && give > 0;
    final color = balanced ? Colors.green : Colors.orange;
    return Row(
      children: [
        Icon(
          balanced ? Icons.balance : Icons.error_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          l10n.balanceSummary(give, receive),
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(width: 8),
        Text(
          balanced ? l10n.balanced : l10n.unbalanced,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
