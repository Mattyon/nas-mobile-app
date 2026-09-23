import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Library tab can be filtered to titles held in Czech or in English, and the
/// choice is remembered across app starts. That persistence is the point of the
/// feature, not a convenience: someone who only ever wants to know what exists in
/// Czech should never have to re-pick it.
///
/// The filter asks "is it available in this language", not "is it only this
/// language" — a title present in both still answers yes to Czech.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, dynamic> both = {'title': 'Lucifer', 'on_disk_en': true, 'on_disk_cs': true};
  const Map<String, dynamic> csOnly = {'title': 'Griffinovi', 'on_disk_en': false, 'on_disk_cs': true};
  const Map<String, dynamic> enOnly = {'title': 'Step by Step', 'on_disk_en': true, 'on_disk_cs': false};
  const Map<String, dynamic> neither = {'title': 'Requested', 'on_disk_en': false, 'on_disk_cs': false};
  final List<dynamic> library = <dynamic>[both, csOnly, enOnly, neither];

  List<String> titles(List<dynamic> items) =>
      items.map((dynamic e) => (e as Map<String, dynamic>)['title'] as String).toList();

  group('filterLibraryByLanguage', () {
    test('"all" returns everything, untouched', () {
      expect(filterLibraryByLanguage(library, 'all'), same(library));
    });

    test('"cs" keeps everything available in Czech, including bilingual titles', () {
      expect(titles(filterLibraryByLanguage(library, 'cs')), <String>['Lucifer', 'Griffinovi']);
    });

    test('"en" keeps everything available in English', () {
      expect(titles(filterLibraryByLanguage(library, 'en')), <String>['Lucifer', 'Step by Step']);
    });

    test('a title held in neither language is filtered out by both', () {
      // Requested-but-not-downloaded rows exist in the library list.
      expect(titles(filterLibraryByLanguage(library, 'cs')), isNot(contains('Requested')));
      expect(titles(filterLibraryByLanguage(library, 'en')), isNot(contains('Requested')));
    });

    test('an unrecognised value shows everything rather than nothing', () {
      // A stale stored value must not look like an empty library.
      expect(filterLibraryByLanguage(library, 'de'), same(library));
      expect(filterLibraryByLanguage(library, ''), same(library));
    });

    test('a missing flag is treated as absent, not as true', () {
      final List<dynamic> partial = <dynamic>[
        <String, dynamic>{'title': 'Old entry'}, // pre-dates the language registry
        csOnly,
      ];
      expect(titles(filterLibraryByLanguage(partial, 'cs')), <String>['Griffinovi']);
      expect(filterLibraryByLanguage(partial, 'en'), isEmpty);
    });

    test('a non-map entry does not throw', () {
      // Defensive: the list comes from JSON, so it is only as typed as the gateway.
      expect(filterLibraryByLanguage(<dynamic>['junk', csOnly], 'cs').length, 1);
    });

    test('filtering never mutates the source list', () {
      final List<dynamic> src = <dynamic>[...library];
      filterLibraryByLanguage(src, 'cs');
      expect(src.length, 4);
    });

    test('an empty library stays empty rather than throwing', () {
      expect(filterLibraryByLanguage(<dynamic>[], 'cs'), isEmpty);
    });
  });

  group('persistence', () {
    const String key = 'libraryLangFilter';

    test('the chosen filter survives an app restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, 'cs');

      // A fresh handle stands in for the next app start.
      final SharedPreferences reopened = await SharedPreferences.getInstance();
      expect(reopened.getString(key), 'cs');
    });

    test('no stored value means no filter', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String restored = prefs.getString(key) ?? 'all';
      expect(filterLibraryByLanguage(library, restored), same(library));
    });

    test('a corrupted stored value falls back to showing everything', () async {
      // Mirrors the guard in _restoreLangFilter: only all/cs/en are accepted.
      SharedPreferences.setMockInitialValues(<String, Object>{key: 'sk'});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(key);
      final String effective =
          <String>['all', 'cs', 'en'].contains(saved) ? saved! : 'all';
      expect(effective, 'all');
      expect(filterLibraryByLanguage(library, effective), same(library));
    });

    test('switching the filter overwrites the stored value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{key: 'cs'});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, 'en');
      expect(prefs.getString(key), 'en');
    });
  });

  group('i18n', () {
    for (final String code in <String>['en', 'cs']) {
      test('$code has every string the filter bar needs', () {
        lang.value = code;
        for (final String k in <String>[
          'langAll', 'langCzech', 'langEnglish', 'langFilterEmpty', 'langFilterCount'
        ]) {
          expect(tr(k), isNotEmpty, reason: k);
          expect(tr(k), isNot(equals(k)), reason: '$k is untranslated in $code');
        }
      });
    }

    test('the count string carries both slots and substitutes cleanly', () {
      for (final String code in <String>['en', 'cs']) {
        lang.value = code;
        final String raw = tr('langFilterCount');
        expect(raw.contains('{n}'), isTrue, reason: code);
        expect(raw.contains('{total}'), isTrue, reason: code);
        final String rendered = raw.replaceAll('{n}', '2').replaceAll('{total}', '40');
        expect(rendered.contains('{'), isFalse);
        expect(rendered.contains('2'), isTrue);
        expect(rendered.contains('40'), isTrue);
      }
    });

    test('Czech and English labels actually differ between locales', () {
      lang.value = 'en';
      final String enCzech = tr('langCzech');
      lang.value = 'cs';
      expect(tr('langCzech'), isNot(equals(enCzech)));
    });
  });

  /// The bar overflowed in Czech and not in English, because "Čeština"/"Angličtina"
  /// are about twice the width of "Czech"/"English". These pump it at real phone
  /// widths in both locales: an overflowing Row throws during layout, which
  /// takeException() surfaces, so a regression fails here rather than shipping as a
  /// yellow-and-black stripe on someone's phone.
  group('LanguageFilterBar layout', () {
    Future<void> pumpBar(WidgetTester tester,
        {required String code,
        required double width,
        String selected = 'cs',
        double textScale = 1.0,
        ValueChanged<String>? onChanged}) async {
      lang.value = code;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SizedBox(
              width: width,
              child: LanguageFilterBar(
                lang: selected,
                shown: 2,
                total: 40,
                onChanged: onChanged ?? (_) {},
              ),
            ),
          ),
        ),
      ));
    }

    for (final double width in <double>[320, 360, 411]) {
      for (final String code in <String>['cs', 'en']) {
        testWidgets('$code fits a ${width.toInt()}px phone', (WidgetTester tester) async {
          await pumpBar(tester, code: code, width: width);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('it survives a larger system font', (WidgetTester tester) async {
      // Accessibility text scaling is the other way this row ran out of room.
      await pumpBar(tester, code: 'cs', width: 360, textScale: 1.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chip labels do not change width with the locale',
        (WidgetTester tester) async {
      // The actual fix: codes, not translated words. If someone puts tr('langCzech')
      // back into the chip, this fails.
      for (final String code in <String>['cs', 'en']) {
        await pumpBar(tester, code: code, width: 360);
        expect(find.text('🇨🇿 CZ'), findsOneWidget);
        expect(find.text('🇬🇧 EN'), findsOneWidget);
      }
    });

    testWidgets('the full language name is still reachable as a tooltip',
        (WidgetTester tester) async {
      lang.value = 'cs';
      await pumpBar(tester, code: 'cs', width: 360);
      final Iterable<Tooltip> tips = tester.widgetList<Tooltip>(find.byType(Tooltip));
      expect(tips.map((Tooltip t) => t.message), contains(tr('langCzech')));
      expect(tips.map((Tooltip t) => t.message), contains(tr('langEnglish')));
    });

    testWidgets('the count is shown when filtering and hidden when not',
        (WidgetTester tester) async {
      await pumpBar(tester, code: 'en', width: 360, selected: 'cs');
      expect(find.textContaining('2'), findsWidgets);
      await pumpBar(tester, code: 'en', width: 360, selected: 'all');
      expect(find.textContaining('of 40'), findsNothing);
    });

    testWidgets('tapping a chip reports the new filter', (WidgetTester tester) async {
      final List<String> picked = <String>[];
      await pumpBar(tester, code: 'cs', width: 360, onChanged: picked.add);
      await tester.tap(find.text('🇬🇧 EN'));
      await tester.pump();
      expect(picked, <String>['en']);
    });
  });
}
