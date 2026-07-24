import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import 'match_balance.dart';
import 'trade_tab.dart';

/// Lifecycle action row for a match card. Mutations are callback-driven so
/// the parent screen can keep using MatchController (#241 / #496).
class MatchCardActions extends StatelessWidget {
  const MatchCardActions({
    super.key,
    required this.user,
    required this.match,
    required this.tab,
    required this.onUpdateStatus,
    required this.onMakeOffer,
    required this.onApplyInventory,
  });

  final User user;
  final TradeMatch match;
  final TradeTab tab;
  final void Function(String newStatus) onUpdateStatus;
  final VoidCallback onMakeOffer;
  final VoidCallback onApplyInventory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (tab) {
      case TradeTab.match_:
        return _actionBar(
          children: [
            TextButton(
              onPressed: () => onUpdateStatus('REJECTED'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.reject),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onMakeOffer, child: Text(l10n.makeOffer)),
          ],
        );
      case TradeTab.offerIn:
        final balanced = matchIsBalanced(user.id, match);
        return _actionBar(
          children: [
            TextButton(
              onPressed: () => onUpdateStatus('REJECTED'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.reject),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onMakeOffer,
              child: Text(l10n.counterOffer),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              // Accept is the non-proposer's, only of a balanced proposal
              // (#297). The backend enforces it too; this just prevents the
              // user from trying an impossible accept.
              onPressed: balanced ? () => onUpdateStatus('ACCEPTED') : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text(balanced ? l10n.accept : l10n.acceptBalanceHint),
            ),
          ],
        );
      case TradeTab.offerOut:
        return _actionBar(
          children: [
            TextButton(
              onPressed: () => onUpdateStatus('REJECTED'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.cancelOffer),
            ),
            Text(
              l10n.waitingForResponse,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        );
      case TradeTab.active:
        return _actionBar(
          children: [
            ElevatedButton(
              onPressed: () => onUpdateStatus('COMPLETED'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text(l10n.markComplete),
            ),
          ],
        );
      case TradeTab.completed:
        if (!match.inventoryApplied) {
          return _actionBar(
            children: [
              OutlinedButton.icon(
                onPressed: onApplyInventory,
                icon: const Icon(Icons.inventory, size: 16),
                label: Text(l10n.updateInventory),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  l10n.inventoryUpdated,
                  style: TextStyle(color: Colors.green[700], fontSize: 13),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _actionBar({required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: children),
      ],
    );
  }
}
