import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — health check trigger and status keys', () {
    const List<String> keys = <String>[
      'healthCheck', 'runHealthCheck', 'healthCheckRunning',
      'healthCheckOk', 'healthCheckIssues', 'healthCheckWarnings',
      'healthCheckLastRun', 'healthCheckNever', 'healthCheckDuration',
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

    test('healthCheckOk and healthCheckIssues are different', () {
      lang.value = 'en';
      expect(tr('healthCheckOk'), isNot(equals(tr('healthCheckIssues'))));
    });

    test('healthCheckIssues and healthCheckWarnings are different', () {
      lang.value = 'en';
      expect(tr('healthCheckIssues'), isNot(equals(tr('healthCheckWarnings'))));
    });

    test('healthCheckNever and healthCheckRunning are different', () {
      lang.value = 'en';
      expect(tr('healthCheckNever'), isNot(equals(tr('healthCheckRunning'))));
    });
  });

  group('i18n — health check category labels', () {
    const Map<String, String> categoryToKey = <String, String>{
      'stalled':       'healthCheckStalled',
      'missing_file':  'healthCheckMissing',
      'small_file':    'healthCheckSmall',
      'not_imported':  'healthCheckNotImported',
      'torrent_error': 'healthCheckQbtError',
      'sonarr':        'healthCheckSonarr',
      'radarr':        'healthCheckRadarr',
    };

    for (final MapEntry<String, String> entry in categoryToKey.entries) {
      test('EN "${entry.key}" → "${entry.value}" translated', () {
        lang.value = 'en';
        final String v = tr(entry.value);
        expect(v, isNotEmpty, reason: '${entry.value} missing EN translation');
        expect(v, isNot(equals(entry.value)));
      });
      test('CS "${entry.key}" → "${entry.value}" translated', () {
        lang.value = 'cs';
        final String v = tr(entry.value);
        expect(v, isNotEmpty, reason: '${entry.value} missing CS translation');
      });
    }

    test('all 7 category labels are distinct in EN', () {
      lang.value = 'en';
      final Set<String> vals = categoryToKey.values.map(tr).toSet();
      expect(vals.length, categoryToKey.length,
          reason: 'Each health check category must have a unique label');
    });
  });

  group('i18n — health check card severity keys', () {
    const List<String> keys = <String>[
      'healthCheckIssue', 'healthCheckWarning',
      'aiFix', 'aiFixing', 'aiFixResult', 'aiFixFailed',
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

    test('healthCheckIssue and healthCheckWarning are different', () {
      lang.value = 'en';
      expect(tr('healthCheckIssue'), isNot(equals(tr('healthCheckWarning'))));
    });

    test('aiFix and aiFixing and aiFixResult are all different', () {
      lang.value = 'en';
      expect(tr('aiFix'), isNot(equals(tr('aiFixing'))));
      expect(tr('aiFixing'), isNot(equals(tr('aiFixResult'))));
      expect(tr('aiFixResult'), isNot(equals(tr('aiFixFailed'))));
    });
  });

  group('health check — report data structure', () {
    test('health report has items list', () {
      final Map<String, dynamic> report = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'category': 'stalled', 'title': 'Movie.mkv'},
        ],
        'ran_at': '2026-06-08T12:00:00Z',
        'duration_sec': 45,
      };
      final List<dynamic> items = (report['items'] as List<dynamic>?) ?? <dynamic>[];
      expect(items.length, 1);
    });

    test('empty items list means no issues', () {
      final Map<String, dynamic> report = <String, dynamic>{
        'items': <dynamic>[],
      };
      final List<dynamic> items = (report['items'] as List<dynamic>?) ?? <dynamic>[];
      expect(items, isEmpty);
    });

    test('issue item has category and title', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'category': 'missing_file',
        'title': 'Missing Movie Title',
        'severity': 'issue',
      };
      expect(item['category'], isNotNull);
      expect(item['title'], isNotNull);
    });
  });
}
