import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — Czech audio grab keys', () {
    const List<String> keys = <String>[
      'czechAudio', 'czechAudioHint',
      'pickLanguage', 'langEnglish', 'langCzech',
      'noCzechAudio', 'noCzechAudioMsg',
      'downloadInEnglish', 'inLibraryBoth',
      'appLanguage', 'langMismatch',
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
  });

  group('i18n — Czech audio key semantics', () {
    test('langEnglish and langCzech are different labels', () {
      lang.value = 'en';
      expect(tr('langEnglish'), isNot(equals(tr('langCzech'))));
    });

    test('czechAudio and czechAudioHint are different labels', () {
      lang.value = 'en';
      expect(tr('czechAudio'), isNot(equals(tr('czechAudioHint'))));
    });

    test('noCzechAudio and noCzechAudioMsg are different', () {
      lang.value = 'en';
      expect(tr('noCzechAudio'), isNot(equals(tr('noCzechAudioMsg'))));
    });

    test('EN noCzechAudioMsg contains {title} placeholder', () {
      lang.value = 'en';
      expect(tr('noCzechAudioMsg').contains('{title}'), isTrue);
    });

    test('EN noCzechAudioMsg contains {tier} placeholder', () {
      lang.value = 'en';
      expect(tr('noCzechAudioMsg').contains('{tier}'), isTrue);
    });

    test('CS noCzechAudioMsg contains {title} placeholder', () {
      lang.value = 'cs';
      expect(tr('noCzechAudioMsg').contains('{title}'), isTrue);
    });

    test('CS noCzechAudioMsg contains {tier} placeholder', () {
      lang.value = 'cs';
      expect(tr('noCzechAudioMsg').contains('{tier}'), isTrue);
    });
  });

  group('Czech audio — message interpolation', () {
    test('both placeholders replaced after interpolation', () {
      lang.value = 'en';
      const String title = 'Inception';
      const String tier = 'balanced';
      final String msg = tr('noCzechAudioMsg')
          .replaceFirst('{title}', title)
          .replaceFirst('{tier}', tier);
      expect(msg.contains('{title}'), isFalse);
      expect(msg.contains('{tier}'), isFalse);
      expect(msg.contains(title), isTrue);
    });

    test('CS interpolation works correctly', () {
      lang.value = 'cs';
      final String msg = tr('noCzechAudioMsg')
          .replaceFirst('{title}', 'Film')
          .replaceFirst('{tier}', 'vyvážené');
      expect(msg.contains('Film'), isTrue);
    });
  });

  group('Czech audio — language ordering logic', () {
    // Mirrors: if (appLang == 'cs') [csTile, enTile] else [enTile, csTile]
    test('CS app language shows Czech tile first', () {
      const String appLang = 'cs';
      final List<String> order =
          appLang == 'cs' ? <String>['cs', 'en'] : <String>['en', 'cs'];
      expect(order.first, 'cs');
    });

    test('EN app language shows English tile first', () {
      const String appLang = 'en';
      final List<String> order =
          appLang == 'cs' ? <String>['cs', 'en'] : <String>['en', 'cs'];
      expect(order.first, 'en');
    });
  });
}
