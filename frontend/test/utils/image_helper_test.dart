import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/image_helper.dart';

/// 1x1 transparent PNG as a base64 data URI.
const _transparentPngDataUri =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M8AAQABAAX3oc3+AAAAAElFTkSuQmCC';

void main() {
  group('buildImage', () {
    testWidgets('default fit is BoxFit.contain (no center-crop) (#329)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: buildImage(_transparentPngDataUri),
            ),
          ),
        ),
      );

      final Image image = tester.widget(find.byType(Image));
      expect(
        image.fit,
        BoxFit.contain,
        reason:
            'Uploaded images must render in full with transparent '
            'padding, not center-cropped via BoxFit.cover',
      );
    });

    testWidgets('explicit fit argument is respected (#329)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: buildImage(_transparentPngDataUri, fit: BoxFit.cover),
            ),
          ),
        ),
      );

      final Image image = tester.widget(find.byType(Image));
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('empty url renders the placeholder, not an Image (#329)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: buildImage('', width: 80, height: 80),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });
}
