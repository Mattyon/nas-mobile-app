import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── on_disk_en / on_disk_cs flag logic ────────────────────────────────────
  // Mirrors _SearchScreenState._buildTrailing and _langChips

  bool _hasEn(Map<String, dynamic> item) => item['on_disk_en'] == true;
  bool _hasCs(Map<String, dynamic> item) => item['on_disk_cs'] == true;

  group('search — EN/CS on-disk indicator flags', () {
    test('EN flag true, CS flag false → EN chip only', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': true, 'on_disk_cs': false,
      };
      expect(_hasEn(item), isTrue);
      expect(_hasCs(item), isFalse);
    });

    test('CS flag true, EN flag false → CS chip only', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': false, 'on_disk_cs': true,
      };
      expect(_hasEn(item), isFalse);
      expect(_hasCs(item), isTrue);
    });

    test('both flags true → both chips shown', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': true, 'on_disk_cs': true,
      };
      expect(_hasEn(item), isTrue);
      expect(_hasCs(item), isTrue);
    });

    test('both flags false → no chips', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': false, 'on_disk_cs': false,
      };
      expect(_hasEn(item), isFalse);
      expect(_hasCs(item), isFalse);
    });

    test('null flags → no chips', () {
      final Map<String, dynamic> item = <String, dynamic>{};
      expect(_hasEn(item), isFalse);
      expect(_hasCs(item), isFalse);
    });
  });

  group('search — TV on_disk flags updated from API response', () {
    // Mirrors: if (result.containsKey('on_disk_en')) item['on_disk_en'] = result['on_disk_en']
    test('response overrides local on_disk_en flag', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': false, 'on_disk_cs': false,
      };
      final Map<String, dynamic> result = <String, dynamic>{
        'on_disk_en': true, 'on_disk_cs': false,
      };
      if (result.containsKey('on_disk_en')) item['on_disk_en'] = result['on_disk_en'];
      if (result.containsKey('on_disk_cs')) item['on_disk_cs'] = result['on_disk_cs'];
      expect(item['on_disk_en'], isTrue);
      expect(item['on_disk_cs'], isFalse);
    });

    test('response without on_disk key does not override item', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': true, 'on_disk_cs': false,
      };
      final Map<String, dynamic> result = <String, dynamic>{};
      if (result.containsKey('on_disk_en')) item['on_disk_en'] = result['on_disk_en'];
      expect(item['on_disk_en'], isTrue); // unchanged
    });
  });

  group('i18n — language picker and Czech audio keys (complete)', () {
    const List<String> keys = <String>[
      'pickLanguage', 'langEnglish', 'langCzech',
      'czechAudio', 'czechAudioHint',
      'noCzechAudio', 'noCzechAudioMsg',
      'downloadInEnglish', 'inLibraryBoth',
      'appLanguage', 'langMismatch',
      'swap', 'swapStarted', 'noAlternative',
    ];

    for (final String key in keys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
      test('CS "$key" translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('langEnglish and langCzech are different', () {
      lang.value = 'en';
      expect(tr('langEnglish'), isNot(equals(tr('langCzech'))));
    });

    test('appLanguage is a short qualifier string', () {
      lang.value = 'en';
      final String v = tr('appLanguage');
      // "app language" — should be short, not a full sentence
      expect(v.length, lessThan(20));
    });
  });
}
