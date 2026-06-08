import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — storage labels', () {
    // Note: EN 'free', 'transcode', 'direct' are untranslated in English
    // (the EN value IS the English word). CS translations differ.
    const List<String> storageKeys = <String>[
      'free', 'storageUsedSuffix', 'transcode', 'direct',
    ];

    for (final String key in storageKeys) {
      test('EN "$key" is non-empty', () {
        lang.value = 'en';
        expect(tr(key), isNotEmpty);
      });
      test('CS "$key" translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('EN free and storageUsedSuffix are different', () {
      lang.value = 'en';
      expect(tr('free'), isNot(equals(tr('storageUsedSuffix'))));
    });

    test('transcode and direct labels are different in CS', () {
      lang.value = 'cs';
      expect(tr('transcode'), isNot(equals(tr('direct'))));
    });
  });

  group('i18n — session screen labels', () {
    const List<String> sessionKeys = <String>[
      'mediaSessions', 'noSessions',
    ];

    for (final String key in sessionKeys) {
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

    test('mediaSessions and noSessions are different', () {
      lang.value = 'en';
      expect(tr('mediaSessions'), isNot(equals(tr('noSessions'))));
    });
  });

  group('i18n — speed limits dialog', () {
    const List<String> speedKeys = <String>[
      'speedLimits', 'dlLimit', 'upLimit', 'pauseAll', 'resumeAll', 'save',
    ];

    for (final String key in speedKeys) {
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

    test('pauseAll and resumeAll are different labels', () {
      lang.value = 'en';
      expect(tr('pauseAll'), isNot(equals(tr('resumeAll'))));
    });

    test('dlLimit and upLimit are different labels', () {
      lang.value = 'en';
      expect(tr('dlLimit'), isNot(equals(tr('upLimit'))));
    });

    test('dlLimit contains "Mbit" (unit hint in label)', () {
      lang.value = 'en';
      expect(tr('dlLimit').toLowerCase().contains('mbit'), isTrue);
    });

    test('all 6 speed limit keys are distinct in EN', () {
      lang.value = 'en';
      final Set<String> vals = speedKeys.map(tr).toSet();
      expect(vals.length, speedKeys.length,
          reason: 'All speed limit labels must be unique');
    });
  });

  group('i18n — disk bar label assembly', () {
    test('storageUsedSuffix can be used in "X% <suffix>" pattern', () {
      lang.value = 'en';
      final String suffix = tr('storageUsedSuffix');
      final String label = '75% $suffix';
      expect(label.contains('%'), isTrue);
      expect(label.contains(suffix), isTrue);
    });

    test('free label can be used in "N GB <free>" pattern', () {
      lang.value = 'en';
      final String freeLabel = tr('free');
      final String label = '2.5 GB $freeLabel';
      expect(label.contains(freeLabel), isTrue);
    });
  });
}
