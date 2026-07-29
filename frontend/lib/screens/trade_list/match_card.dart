import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_local_datetime.dart';
import '../../utils/group_display.dart';
import 'match_balance.dart';
import 'match_card_actions.dart';
import 'match_items.dart';
import 'match_status_chrome.dart';
import 'trade_tab.dart';

/// Single match row on the trades list: header chrome, items, balance, actions.
///
/// Presentation only — mutations and navigation arrive via callbacks (#496).
class TradeMatchCard extends StatelessWidget {
  const TradeMatchCard({
    super.key,
    required this.user,
    required this.match,
    required this.tab,
    required this.onOpenChat,
    required this.onUpdateStatus,
    required this.onMakeOffer,
    required this.onApplyInventory,
  });

  final User user;
  final TradeMatch match;
  final TradeTab tab;
  final VoidCallback onOpenChat;
  final void Function(String newStatus) onUpdateStatus;
  final VoidCallback onMakeOffer;
  final VoidCallback onApplyInventory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final otherName = match.hasOtherUser()
        ? match.otherUser.username
        : l10n.unknownUser;
    // #476: UTC API timestamp → device-local wall clock for display.
    final createdAtLabel = match.hasCreatedAt()
        ? formatLocalDateTime(match.createdAt)
        : null;
    // #534 / #466: group label for the give/receive item rows (same value on
    // both sides by ADR 0001; shown twice for UI balance).
    final itemGroupLabel = match.hasGroupName()
        ? groupLabel(
            match.groupName,
            match.hasGroupDisplayName() ? match.groupDisplayName : null,
          )
        : null;

    final cancelled = match.status == 'CANCELLED';
    return Opacity(
      opacity: cancelled ? 0.72 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // #314: completed matches stay conversable — the card opens the chat
          // thread on every tab, same as while trading. CANCELLED (ADR 0010)
          // also keeps chat for history/SYSTEM cancel reason.
          onTap: onOpenChat,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: user + status
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.secondaryColor.withValues(
                        alpha: 0.1,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppTheme.secondaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            otherName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          MatchStatusChip(status: match.status),
                          // ADR 0012 / #477: prior-history annotation after rematch.
                          if (match.hasLastTerminalStatus()) ...[
                            const SizedBox(height: 2),
                            PriorHistoryAnnotation(match: match),
                          ],
                          // #322 / ADR 0001 / #534: event name stays on the card
                          // header (position unchanged). Group name is shown on
                          // the give/receive item rows instead — see match_items.
                          // Real matches always have eventName; guard so
                          // synthetic/test matches without it render nothing.
                          if (match.hasEventName()) ...[
                            const SizedBox(height: 2),
                            Text(
                              // #534: "Event: {name}" / "イベント : {name}"
                              l10n.matchEventLabel(match.eventName),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          // #476: match created_at in device local time.
                          if (createdAtLabel != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              createdAtLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // #314: the Message affordance is shown on every tab,
                    // including completed matches (chat remains open after a
                    // trade is done, same as while trading).
                    FilledButton.tonal(
                      onPressed: onOpenChat,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l10n.messageAction),
                    ),
                  ],
                ),

                // Items section
                if (match.selectedItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  MatchSelectedItems(
                    userId: user.id,
                    match: match,
                    groupLabel: itemGroupLabel,
                  ),
                ] else if (match.userHaves.isNotEmpty ||
                    match.userWants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  MatchPotentialItems(match: match, groupLabel: itemGroupLabel),
                ],

                // Balance indicator on an open proposal (#297)
                if (match.status == 'OFFERED') ...[
                  const SizedBox(height: 8),
                  MatchBalanceIndicator.forMatch(userId: user.id, match: match),
                ],

                // Action buttons (none for CANCELLED — Done tab history only)
                if (!cancelled)
                  MatchCardActions(
                    user: user,
                    match: match,
                    tab: tab,
                    onUpdateStatus: onUpdateStatus,
                    onMakeOffer: onMakeOffer,
                    onApplyInventory: onApplyInventory,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
