import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/image_helper.dart';

void main() {
  testWidgets('buildImage returns placeholder icon when url is missing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: buildImage(null, width: 40, height: 40))),
    );

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('buildImage configures network images for gapless playback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildImage(
            'https://example.com/image.png',
            width: 40,
            height: 40,
          ),
        ),
      ),
    );

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    expect(
      find.ancestor(of: imageFinder, matching: find.byType(RepaintBoundary)),
      findsOneWidget,
    );

    final image = tester.widget<Image>(imageFinder);
    expect(image.gaplessPlayback, isTrue);
    expect(image.frameBuilder, isNotNull);
  });
}
