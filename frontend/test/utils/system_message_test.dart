import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/utils/system_message.dart';

Future<AppLocalizations> _l10n(Locale locale) {
  return AppLocalizations.delegate.load(locale);
}

void main() {
  group('localizeSystemMessage (#462)', () {
    test('maps MERCH_DELETED and legacy English under en', () async {
      final l10n = await _l10n(const Locale('en'));
      expect(
        localizeSystemMessage(l10n, cancelReasonMerchDeleted),
        'This match was cancelled because a traded item was deleted.',
      );
      expect(
        localizeSystemMessage(
          l10n,
          'This match was cancelled because a traded item was deleted.',
        ),
        'This match was cancelled because a traded item was deleted.',
      );
      expect(
        localizeSystemMessage(l10n, ''),
        'This match was cancelled because a traded item was deleted.',
      );
    });

    test('maps INVENTORY_CAPACITY and legacy English under en', () async {
      final l10n = await _l10n(const Locale('en'));
      expect(
        localizeSystemMessage(l10n, cancelReasonInventoryCapacity),
        'This match was cancelled because inventory no longer supports a mutual trade.',
      );
      expect(
        localizeSystemMessage(
          l10n,
          'This match was cancelled because inventory no longer supports a mutual trade.',
        ),
        'This match was cancelled because inventory no longer supports a mutual trade.',
      );
    });

    test('maps reason codes to Japanese under ja', () async {
      final l10n = await _l10n(const Locale('ja'));
      expect(
        localizeSystemMessage(l10n, cancelReasonMerchDeleted),
        '取引アイテムが削除されたため、このマッチはキャンセルされました。',
      );
      expect(
        localizeSystemMessage(l10n, cancelReasonInventoryCapacity),
        '在庫が相互取引を支えられなくなったため、このマッチはキャンセルされました。',
      );
      // Legacy English body still resolves to JA display copy.
      expect(
        localizeSystemMessage(
          l10n,
          'This match was cancelled because a traded item was deleted.',
        ),
        '取引アイテムが削除されたため、このマッチはキャンセルされました。',
      );
      expect(
        localizeSystemMessage(
          l10n,
          'This match was cancelled because inventory no longer supports a mutual trade.',
        ),
        '在庫が相互取引を支えられなくなったため、このマッチはキャンセルされました。',
      );
    });

    test('unknown content is returned unchanged', () async {
      final l10n = await _l10n(const Locale('ja'));
      expect(localizeSystemMessage(l10n, 'custom note'), 'custom note');
    });
  });
}
