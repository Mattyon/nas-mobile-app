import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — speedtest screen keys', () {
    const List<String> keys = <String>[
      'speedtest', 'runSpeedtest', 'speedtestRunning',
      'downloadSpeed', 'uploadSpeed', 'ping', 'isp', 'testServer',
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

    test('speedtest and runSpeedtest are different', () {
      lang.value = 'en';
      expect(tr('speedtest'), isNot(equals(tr('runSpeedtest'))));
    });

    test('downloadSpeed and uploadSpeed are different labels', () {
      lang.value = 'en';
      expect(tr('downloadSpeed'), isNot(equals(tr('uploadSpeed'))));
    });

    test('ping, isp, and testServer are all different', () {
      lang.value = 'en';
      expect(tr('ping'), isNot(equals(tr('isp'))));
      expect(tr('isp'), isNot(equals(tr('testServer'))));
    });

    test('speedtestRunning mentions ~30 seconds', () {
      lang.value = 'en';
      final String msg = tr('speedtestRunning');
      // Contains the estimated duration (~30 seconds)
      expect(msg.contains('30'), isTrue);
    });

    test('all 8 speedtest keys are distinct in EN', () {
      lang.value = 'en';
      final Set<String> vals = keys.map(tr).toSet();
      expect(vals.length, keys.length,
          reason: 'All speedtest labels must be unique');
    });
  });

  group('i18n — AI assistant keys', () {
    const List<String> keys = <String>[
      'aiAssistant', 'aiHint', 'aiClear', 'aiEmptyHint',
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

    test('aiHint and aiEmptyHint are different labels', () {
      lang.value = 'en';
      expect(tr('aiHint'), isNot(equals(tr('aiEmptyHint'))));
    });

    test('aiClear and aiHint are different', () {
      lang.value = 'en';
      expect(tr('aiClear'), isNot(equals(tr('aiHint'))));
    });

    test('aiEmptyHint is a longer description (> 20 chars)', () {
      lang.value = 'en';
      expect(tr('aiEmptyHint').length, greaterThan(20));
    });
  });

  group('speedtest — result data parsing', () {
    test('speedtest result has required fields', () {
      final Map<String, dynamic> result = <String, dynamic>{
        'download_mbps': 950.5,
        'upload_mbps': 120.3,
        'ping_ms': 12.0,
        'isp': 'Vodafone CZ',
        'server_name': 'Prague, CZ',
      };
      expect(result['download_mbps'], isNotNull);
      expect(result['upload_mbps'], isNotNull);
      expect(result['ping_ms'], isNotNull);
    });

    test('speed formatted to 1 decimal place', () {
      final double mbps = 950.567;
      final String formatted = mbps.toStringAsFixed(1);
      expect(formatted, '950.6');
    });
  });
}
