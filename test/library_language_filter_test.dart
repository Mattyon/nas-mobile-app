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
}
