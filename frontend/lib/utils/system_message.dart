import '../l10n/app_localizations.dart';

/// Stable reason codes written by the backend into SYSTEM message `content`
/// ([#462](https://github.com/menonu/ymatch/issues/462)). Display strings live
/// in ARB / [AppLocalizations] — never show the raw code to users.
const String cancelReasonMerchDeleted = 'MERCH_DELETED';
const String cancelReasonInventoryCapacity = 'INVENTORY_CAPACITY';

/// Legacy English bodies written before reason codes (#462). Mapped so
/// existing rows still localize.
const String _legacyMerchDeleted =
    'This match was cancelled because a traded item was deleted.';
const String _legacyInventoryCapacity =
    'This match was cancelled because inventory no longer supports a mutual trade.';

/// Localize a SYSTEM message `content` value for the chat notice.
///
/// Handles:
/// - stable reason codes (`MERCH_DELETED`, `INVENTORY_CAPACITY`)
/// - pre-#462 English prose still in the DB
/// - empty content → merch-delete wording (historical fallback)
/// - unknown values → returned as-is so custom/future copy is not swallowed
String localizeSystemMessage(AppLocalizations l10n, String content) {
  switch (content) {
    case cancelReasonMerchDeleted:
    case _legacyMerchDeleted:
    case '':
      return l10n.matchCancelledSystemMessage;
    case cancelReasonInventoryCapacity:
    case _legacyInventoryCapacity:
      return l10n.matchCancelledInventoryCapacity;
    default:
      return content;
  }
}
