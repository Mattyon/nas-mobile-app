import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/main.dart';

/// The "missing episodes" marker on a library row.
///
/// The gateway already had these numbers — Sonarr returns episodeFileCount and
/// episodeCount in the `statistics` object on the series list the library endpoint
/// fetches anyway — and threw them away, so there was no way to tell a complete show
/// from one with a gap. "Step by Step" sat at 159 of 160 for weeks, invisibly.
///
/// The badge leads with a number rather than a translated word so it is the same
/// width in Czech as in English. The language-filter chips had to be rewritten for
/// exactly that reason, and a badge sits in the same already-crowded subtitle row.
void main() {
  Map<String, dynamic> series({int? have, int? total, int? missing}) =>
      <String, dynamic>{
        'title': 'Step by Step',
        if (have != null) 'episode_file_count': have,
        if (total != null) 'episode_count': total,
        if (missing != null) 'missing_count': missing,
      };

  group('missingEpisodeCount', () {
    test('it reports the gap', () {
      expect(missingEpisodeCount(series(have: 159, total: 160, missing: 1)), 1);
    });

    test('a complete series has nothing to report', () {
      // Zero and null are the same answer to the caller: draw no badge. "0 missing"
      // on a finished show is noise.
      expect(missingEpisodeCount(series(have: 62, total: 62, missing: 0)), isNull);
    });

    test('a movie carries no episode counts at all', () {
      expect(missingEpisodeCount(<String, dynamic>{'title': 'Dune'}), isNull);
    });

    test('a non-integer value does not throw', () {
      // The map comes from JSON, so it is only as typed as the gateway.
      expect(missingEpisodeCount(<String, dynamic>{'missing_count': '3'}), isNull);
      expect(missingEpisodeCount(<String, dynamic>{'missing_count': null}), isNull);
    });

    test('a negative count is not a gap', () {
      expect(missingEpisodeCount(<String, dynamic>{'missing_count': -2}), isNull);
    });
  });

  group('IncompleteBadge', () {
    Future<void> pump(WidgetTester tester, Map<String, dynamic> item,
        {String code = 'en'}) async {
      lang.value = code;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: IncompleteBadge(item: item)))));
    }

    testWidgets('it shows the number of missing episodes', (WidgetTester tester) async {
      await pump(tester, series(have: 159, total: 160, missing: 1));
      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a complete series renders nothing at all', (WidgetTester tester) async {
      await pump(tester, series(have: 62, total: 62, missing: 0));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(tester.getSize(find.byType(IncompleteBadge)), Size.zero);
    });

    testWidgets('a movie renders nothing', (WidgetTester tester) async {
      await pump(tester, <String, dynamic>{'title': 'Dune'});
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('the tooltip gives the full counts', (WidgetTester tester) async {
      await pump(tester, series(have: 159, total: 160, missing: 1));
      final Tooltip tip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('159'));
      expect(tip.message, contains('160'));
    });

    testWidgets('it falls back to the count when totals are absent',
        (WidgetTester tester) async {
      // An older gateway sends missing_count without the other two.
      await pump(tester, series(missing: 4));
      final Tooltip tip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('4'));
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('the badge is the same width in Czech as in English',
        (WidgetTester tester) async {
      // The whole reason the count leads and the words live in the tooltip.
      await pump(tester, series(have: 159, total: 160, missing: 1), code: 'en');
      final Size en = tester.getSize(find.byType(IncompleteBadge));
      await pump(tester, series(have: 159, total: 160, missing: 1), code: 'cs');
      expect(tester.getSize(find.byType(IncompleteBadge)), en);
    });

    testWidgets('the tooltip is actually translated', (WidgetTester tester) async {
      await pump(tester, series(have: 159, total: 160, missing: 1), code: 'en');
      final String enTip = tester.widget<Tooltip>(find.byType(Tooltip)).message!;
      await pump(tester, series(have: 159, total: 160, missing: 1), code: 'cs');
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, isNot(equals(enTip)));
    });
  });

  group('i18n', () {
    for (final String code in <String>['en', 'cs']) {
      test('$code has both strings with their placeholders', () {
        lang.value = code;
        expect(tr('episodesDownloaded'), contains('{have}'));
        expect(tr('episodesDownloaded'), contains('{total}'));
        expect(tr('episodesMissing'), contains('{n}'));
      });

      test('$code substitutes cleanly', () {
        lang.value = code;
        final String rendered = tr('episodesDownloaded')
            .replaceAll('{have}', '159')
            .replaceAll('{total}', '160');
        expect(rendered.contains('{'), isFalse);
        expect(rendered, contains('159'));
      });
    }
  });
}
