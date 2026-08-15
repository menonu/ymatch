// Widget tests for CommunityCard (#570).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/widgets/community_card.dart';

Widget _wrap(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('shows Community title and icon-only X / Discord buttons', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const CommunityCard()));
    await tester.pumpAndSettle();

    expect(find.text('Community'), findsOneWidget);
    expect(find.byKey(const Key('community-x')), findsOneWidget);
    expect(find.byKey(const Key('community-discord')), findsOneWidget);
    expect(find.byTooltip('X'), findsOneWidget);
    expect(find.byTooltip('Discord'), findsOneWidget);
    // Visible labels for the networks must not appear — icons only.
    expect(find.text('X'), findsNothing);
    expect(find.text('Discord'), findsNothing);
  });

  testWidgets('Japanese locale uses コミュニティ as the card title', (tester) async {
    await tester.pumpWidget(
      _wrap(const CommunityCard(), locale: const Locale('ja')),
    );
    await tester.pumpAndSettle();

    expect(find.text('コミュニティ'), findsOneWidget);
    expect(find.text('Community'), findsNothing);
  });

  testWidgets('tapping X launches the official X profile', (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(
        CommunityCard(
          launchUrlOverride: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('community-x')));
    await tester.pump();

    expect(launched, [CommunityCard.xUri]);
    expect(launched.single.toString(), 'https://x.com/ymatchdev');
  });

  testWidgets('tapping Discord launches the official invite', (tester) async {
    final launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(
        CommunityCard(
          launchUrlOverride: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('community-discord')));
    await tester.pump();

    expect(launched, [CommunityCard.discordUri]);
    expect(launched.single.toString(), 'https://discord.gg/QWcCJspb7T');
  });

  testWidgets('failed launch shows a snackbar', (tester) async {
    await tester.pumpWidget(
      _wrap(CommunityCard(launchUrlOverride: (_) async => false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('community-x')));
    await tester.pump();

    expect(find.textContaining('Could not open link'), findsOneWidget);
  });
}
