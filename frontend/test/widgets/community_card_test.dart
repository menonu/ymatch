// Widget tests for CommunityCard (#570).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  test(
    'resolveHttpsUrl accepts https and rejects empty / non-https (#572)',
    () {
      expect(
        CommunityCard.resolveHttpsUrl('https://x.com/ymatchdev'),
        Uri.parse('https://x.com/ymatchdev'),
      );
      expect(
        CommunityCard.resolveHttpsUrl('  https://discord.gg/invite  '),
        Uri.parse('https://discord.gg/invite'),
      );
      expect(CommunityCard.resolveHttpsUrl(''), isNull);
      expect(CommunityCard.resolveHttpsUrl('   '), isNull);
      expect(CommunityCard.resolveHttpsUrl('http://x.com/ymatchdev'), isNull);
      expect(CommunityCard.resolveHttpsUrl('javascript:alert(1)'), isNull);
      expect(CommunityCard.resolveHttpsUrl('not a url'), isNull);
    },
  );

  testWidgets('hides X and Discord when URLs are not injected (#572)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const CommunityCard()));
    await tester.pumpAndSettle();

    expect(find.text('Community'), findsOneWidget);
    expect(find.byKey(const Key('community-x')), findsNothing);
    expect(find.byKey(const Key('community-discord')), findsNothing);
  });

  testWidgets('shows icon-only X / Discord when https URLs are injected', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const CommunityCard(
          xProfileUrl: 'https://x.com/ymatchdev',
          discordInviteUrl: 'https://discord.gg/test-invite',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community-x')), findsOneWidget);
    expect(find.byKey(const Key('community-discord')), findsOneWidget);
    expect(find.byTooltip('X'), findsOneWidget);
    expect(find.byTooltip('Discord'), findsOneWidget);
    // Visible labels for the networks must not appear — icons only.
    expect(find.text('X'), findsNothing);
    expect(find.text('Discord'), findsNothing);
    expect(
      _svgAssets(tester),
      containsAll([CommunityCard.xIconAsset, CommunityCard.discordIconAsset]),
    );
  });

  testWidgets('Japanese locale uses コミュニティ as the card title', (tester) async {
    await tester.pumpWidget(
      _wrap(const CommunityCard(), locale: const Locale('ja')),
    );
    await tester.pumpAndSettle();

    expect(find.text('コミュニティ'), findsOneWidget);
    expect(find.text('Community'), findsNothing);
  });

  testWidgets('tapping X launches the injected profile URL (#572)', (
    tester,
  ) async {
    const xUrl = 'https://x.com/ymatchdev';
    final launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(
        CommunityCard(
          xProfileUrl: xUrl,
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

    expect(launched.single.toString(), xUrl);
  });

  testWidgets('tapping Discord launches the injected invite URL (#572)', (
    tester,
  ) async {
    const discordUrl = 'https://discord.gg/test-invite';
    final launched = <Uri>[];
    await tester.pumpWidget(
      _wrap(
        CommunityCard(
          discordInviteUrl: discordUrl,
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

    expect(launched.single.toString(), discordUrl);
  });

  testWidgets('failed launch shows a snackbar', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CommunityCard(
          xProfileUrl: 'https://x.com/ymatchdev',
          launchUrlOverride: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('community-x')));
    await tester.pump();

    expect(find.textContaining('Could not open link'), findsOneWidget);
  });
}

Iterable<String> _svgAssets(WidgetTester tester) {
  return tester.widgetList<SvgPicture>(find.byType(SvgPicture)).map((picture) {
    final loader = picture.bytesLoader;
    return loader is SvgAssetLoader ? loader.assetName : null;
  }).whereType<String>();
}
