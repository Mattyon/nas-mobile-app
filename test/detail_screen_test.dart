import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — detail screen keys', () {
    const List<String> keys = <String>[
      'cast', 'seasons', 'showMore', 'showLess', 'director',
      'movie', 'tv', 'download', 'onDisk', 'inLibrary', 'inLibraryBoth',
    ];

    for (final String key in keys) {
      test('EN "$key" is translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });

      test('CS "$key" is translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('showMore and showLess are different in EN', () {
      lang.value = 'en';
      expect(tr('showMore'), isNot(equals(tr('showLess'))));
    });

    test('showMore and showLess are different in CS', () {
      lang.value = 'cs';
      expect(tr('showMore'), isNot(equals(tr('showLess'))));
    });

    test('cast and director are different labels', () {
      lang.value = 'en';
      expect(tr('cast'), isNot(equals(tr('director'))));
    });

    test('seasons is different from cast', () {
      lang.value = 'en';
      expect(tr('seasons'), isNot(equals(tr('cast'))));
    });

    test('movie and tv are different labels', () {
      lang.value = 'en';
      expect(tr('movie'), isNot(equals(tr('tv'))));
    });
  });

  group('i18n — detail screen quality tier keys', () {
    const List<String> tiers = <String>['fast', 'balanced', 'best'];

    for (final String tier in tiers) {
      test('EN "$tier" is translated', () {
        lang.value = 'en';
        final String v = tr(tier);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(tier)));
      });

      test('CS "$tier" is translated', () {
        lang.value = 'cs';
        final String v = tr(tier);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(tier)));
      });
    }

    test('all three tier labels are distinct in EN', () {
      lang.value = 'en';
      final Set<String> vals = tiers.map(tr).toSet();
      expect(vals.length, 3);
    });

    test('all three tier labels are distinct in CS', () {
      lang.value = 'cs';
      final Set<String> vals = tiers.map(tr).toSet();
      expect(vals.length, 3);
    });
  });

  group('detail screen — data parsing', () {
    test('cast list parsed from credits.cast', () {
      final Map<String, dynamic> credits = <String, dynamic>{
        'cast': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Actor One', 'character': 'Hero'},
          <String, dynamic>{'name': 'Actor Two', 'character': 'Villain'},
        ],
      };
      final List<dynamic> cast =
          (credits['cast'] as List<dynamic>?) ?? <dynamic>[];
      expect(cast.length, 2);
      expect((cast[0] as Map<String, dynamic>)['name'], 'Actor One');
    });

    test('empty cast list returns empty', () {
      final Map<String, dynamic> credits = <String, dynamic>{
        'cast': <Map<String, dynamic>>[],
      };
      final List<dynamic> cast =
          (credits['cast'] as List<dynamic>?) ?? <dynamic>[];
      expect(cast, isEmpty);
    });

    test('seasons list parsed from number_of_seasons', () {
      final Map<String, dynamic> tvDetail = <String, dynamic>{
        'name': 'Breaking Bad',
        'number_of_seasons': 5,
        'seasons': <dynamic>[],
      };
      expect(tvDetail['number_of_seasons'], 5);
    });
  });
}
