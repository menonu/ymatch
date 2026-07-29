import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/utils/image_helper.dart';

/// 1x1 transparent PNG as a base64 data URI.
const _transparentPngDataUri =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M8AAQABAAX3oc3+AAAAAElFTkSuQmCC';

Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('showZoomedImage (#540)', () {
    testWidgets('opens a zoom viewer for a non-empty photo URL', (
      tester,
    ) async {
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showZoomedImage(context, _transparentPngDataUri),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zoomed_image_viewer')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      // Image from the data URI is present in the viewer.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('close button dismisses the zoom viewer', (tester) async {
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showZoomedImage(context, _transparentPngDataUri),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zoomed_image_viewer')), findsOneWidget);

      await tester.tap(find.byKey(const Key('zoomed_image_close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zoomed_image_viewer')), findsNothing);
    });

    testWidgets('no-ops for null or empty URL (no dialog)', (tester) async {
      await tester.pumpWidget(
        _localized(
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showZoomedImage(context, null),
                  child: const Text('null'),
                ),
                TextButton(
                  onPressed: () => showZoomedImage(context, ''),
                  child: const Text('empty'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('null'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zoomed_image_viewer')), findsNothing);

      await tester.tap(find.text('empty'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zoomed_image_viewer')), findsNothing);
    });
  });

  group('ZoomableImage (#540)', () {
    testWidgets('tap opens zoom viewer when photo URL is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _localized(
          ZoomableImage(
            key: const Key('thumb'),
            photoUrl: _transparentPngDataUri,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('thumb')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zoomed_image_viewer')), findsOneWidget);
    });

    testWidgets('tap does nothing when photo URL is missing', (tester) async {
      await tester.pumpWidget(
        _localized(
          ZoomableImage(
            key: const Key('thumb'),
            photoUrl: null,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('thumb')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zoomed_image_viewer')), findsNothing);
    });
  });
}
