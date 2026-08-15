// Widget tests for CommunityCard (#570, #572, #573).

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

  test('hardcoded GitHub repo URL is public https (#573)', () {
    expect(CommunityCard.githubRepoUrl, 'https://github.com/menonu/ymatch');
    expect(
      CommunityCard.resolveHttpsUrl(CommunityCard.githubRepoUrl),
      Uri.parse(CommunityCard.githubRepoUrl),
    );
  });

  testWidgets(
    'always shows GitHub; hides X and Discord when not injected (#572, #573)',
    (tester) async {
      await tester.pumpWidget(_wrap(const CommunityCard()));
      await tester.pumpAndSettle();

      expect(find.text('Community'), findsOneWidget);
      expect(find.byKey(const Key('community-github')), findsOneWidget);
      expect(find.byTooltip('GitHub'), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);
      expect(find.byKey(const Key('community-x')), findsNothing);
      expect(find.byKey(const Key('community-discord')), findsNothing);
      expect(_svgAssets(tester), [CommunityCard.githubIconAsset]);
    },
  );

  testWidgets('shows icon-only X / Discord / GitHub when URLs are set', (
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
    expect(find.byKey(const Key('community-github')), findsOneWidget);
    expect(find.byTooltip('X'), findsOneWidget);
    expect(find.byTooltip('Discord'), findsOneWidget);
    expect(find.byTooltip('GitHub'), findsOneWidget);
    // Visible labels for the networks must not appear — icons only.
    expect(find.text('X'), findsNothing);
    expect(find.text('Discord'), findsNothing);
    expect(find.text('GitHub'), findsNothing);
    expect(
      _svgAssets(tester),
      containsAll([
        CommunityCard.xIconAsset,
        CommunityCard.discordIconAsset,
        CommunityCard.githubIconAsset,
      ]),
    );
  });

  testWidgets('Japanese locale uses コミュニティ as the card title', (tester) async {
    await tester.pumpWidget(
      _wrap(const CommunityCard(), locale: const Locale('ja')),
    );
    await tester.pumpAndSettle();

    expect(find.text('コミュニティ'), findsOneWidget);
    expect(find.text('Community'), findsNothing);
    expect(find.byTooltip('GitHub'), findsOneWidget);
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

  testWidgets('tapping GitHub launches the hardcoded repo URL (#573)', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(const Key('community-github')));
    await tester.pump();

    expect(launched.single.toString(), CommunityCard.githubRepoUrl);
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
