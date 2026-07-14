import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/models.dart';
import 'package:frontend/services/api_client.dart';
import 'package:frontend/services/config_service.dart';
import 'package:frontend/utils/inventory_export.dart';
import 'package:frontend/widgets/export_inventory_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Wraps [child] with the localization delegates so the dialog's
/// `AppLocalizations.of(context)` resolves strings in widget tests.
Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

User _user() => User()
  ..id = 1
  ..username = 'me';

/// A single inventory row as proto3 JSON (camelCase field names), matching
/// what the backend's serde layer emits and `mergeFromProto3Json` consumes.
Map<String, dynamic> _row({
  required int merchId,
  required String status,
  required int quantity,
  required String merchName,
  required String groupName,
}) => {
  'merchId': merchId,
  'status': status,
  'quantity': quantity,
  'merchName': merchName,
  'groupName': groupName,
};

/// Fixture scoped to group "Pens": HAVE a*2 + b, WANT c*3, TRADE a.
List<Map<String, dynamic>> _fixture() => [
  _row(
    merchId: 1,
    status: 'HAVE',
    quantity: 2,
    merchName: 'a',
    groupName: 'Pens',
  ),
  _row(
    merchId: 2,
    status: 'HAVE',
    quantity: 1,
    merchName: 'b',
    groupName: 'Pens',
  ),
  _row(
    merchId: 3,
    status: 'WANT',
    quantity: 3,
    merchName: 'c',
    groupName: 'Pens',
  ),
  _row(
    merchId: 4,
    status: 'TRADE',
    quantity: 1,
    merchName: 'a',
    groupName: 'Pens',
  ),
];

/// An [ApiClient] backed by a [MockClient] that returns [body] for any GET.
/// Only `inventoryProvider(1)` is watched by the dialog, so this single
/// response is all that's needed.
ApiClient _clientReturning(String body) {
  final config = ConfigService()..setBaseUrlForTest('http://localhost:3000');
  return ApiClient(
    config,
    client: MockClient((request) async => http.Response(body, 200)),
  );
}

Widget _tree(String inventoryJson) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWith((ref) => _clientReturning(inventoryJson)),
  ],
  child: _localized(
    Scaffold(
      body: Center(
        // Mirror real usage: the dialog is opened via showDialog, so its
        // Copy action's Navigator.pop closes the dialog route (not the home).
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => ExportInventoryDialog(
                user: _user(),
                displayGroupName: 'Pens',
                rawGroup: 'Pens',
              ),
            ),
            child: const Text('__open_export__'),
          ),
        ),
      ),
    ),
  ),
);

/// Open the dialog via its trigger button and settle. Call after pumpWidget.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('__open_export__'));
  await tester.pumpAndSettle();
}

/// The export preview is rendered as a single multi-line [SelectableText], so
/// exact-match `find.text` won't hit it. Read its `data` directly instead.
String _preview(WidgetTester tester) {
  final w = tester.widget<SelectableText>(find.byType(SelectableText));
  return w.data ?? '';
}

const _timeout = Timeout(Duration(seconds: 30));

void main() {
  testWidgets(
    'default state previews all three statuses in basic format (ADR 0007)',
    (tester) async {
      await tester.pumpWidget(_tree(jsonEncode(_fixture())));
      await _open(tester);

      // Labels are en: Own / Wish / For Trade.
      expect(_preview(tester), 'Own: a*2, b\nWish: c*3\nFor Trade: a');
    },
    timeout: _timeout,
  );

  testWidgets('unchecking Own removes the HAVE line from the preview', (
    tester,
  ) async {
    await tester.pumpWidget(_tree(jsonEncode(_fixture())));
    await _open(tester);

    expect(_preview(tester), 'Own: a*2, b\nWish: c*3\nFor Trade: a');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Own'));
    await tester.pumpAndSettle();

    expect(_preview(tester), 'Wish: c*3\nFor Trade: a');
  }, timeout: _timeout);

  testWidgets('switching to CSV format shows the CSV header + rows', (
    tester,
  ) async {
    await tester.pumpWidget(_tree(jsonEncode(_fixture())));
    await _open(tester);

    // Open the format dropdown and pick CSV.
    await tester.tap(find.byType(DropdownButton<ExportFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV').last);
    await tester.pumpAndSettle();

    final rendered = _preview(tester);
    expect(rendered, contains('status,item,quantity'));
    expect(rendered, contains('Own,a,2'));
    expect(rendered, contains('Own,b,1'));
    expect(rendered, contains('Wish,c,3'));
    expect(rendered, contains('For Trade,a,1'));
  }, timeout: _timeout);

  // Note: the Copy button's clipboard write (`Clipboard.setData`) is a trivial
  // stdlib call and the platform-clipboard channel is not stubbed here — the
  // formatter itself is exhaustively covered by inventory_export_test.dart.
  // These widget tests pin the dialog wiring: preview, checkbox toggling,
  // format switching, and the Copy-disabled-when-empty state.

  testWidgets('Copy is disabled when nothing is selected to export', (
    tester,
  ) async {
    await tester.pumpWidget(_tree(jsonEncode(_fixture())));
    await _open(tester);

    // Uncheck all three.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Own'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Wish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'For Trade'));
    await tester.pumpAndSettle();

    // The empty hint is shown and the Copy button is disabled.
    expect(_preview(tester), 'Nothing selected to export');
    final copyButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Copy'),
    );
    expect(copyButton.onPressed, isNull);
  }, timeout: _timeout);
}
