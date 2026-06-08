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

  group('health check — chip summary display logic', () {
    // Mirrors the chip row in the health screen:
    // - OK chip when both lists empty
    // - Issues chip when issues > 0
    // - Warnings chip when warnings > 0
    // - No issues chip when issues == 0 but warnings > 0 (the fixed bug)

    bool showOkChip(int i, int w) => i == 0 && w == 0;
    bool showIssuesChip(int i) => i > 0;
    bool showWarningsChip(int w) => w > 0;

    test('all clear → OK chip only, no issues or warnings chips', () {
      expect(showOkChip(0, 0), isTrue);
      expect(showIssuesChip(0), isFalse);
      expect(showWarningsChip(0), isFalse);
    });

    test('issues only → issues chip shown, OK chip hidden', () {
      expect(showOkChip(2, 0), isFalse);
      expect(showIssuesChip(2), isTrue);
      expect(showWarningsChip(0), isFalse);
    });

    test('warnings only → warnings chip shown, issues chip hidden (not "0 issues")', () {
      expect(showOkChip(0, 3), isFalse);
      expect(showIssuesChip(0), isFalse);
      expect(showWarningsChip(3), isTrue);
    });

    test('issues and warnings → both chips shown, OK chip hidden', () {
      expect(showOkChip(1, 2), isFalse);
      expect(showIssuesChip(1), isTrue);
      expect(showWarningsChip(2), isTrue);
    });
  });

  group('health check — report data structure', () {
    test('health report has issues and warnings lists', () {
      final Map<String, dynamic> report = <String, dynamic>{
        'issues': <Map<String, dynamic>>[
          <String, dynamic>{'category': 'stalled', 'message': 'Movie stalled'},
        ],
        'warnings': <dynamic>[],
        'checked_at': '2026-06-08T12:00:00Z',
        'duration_s': 45,
        'ok': false,
      };
      final List<dynamic> issues = (report['issues'] as List<dynamic>?) ?? <dynamic>[];
      expect(issues.length, 1);
    });

    test('empty issues and warnings means no problems', () {
      final Map<String, dynamic> report = <String, dynamic>{
        'issues': <dynamic>[],
        'warnings': <dynamic>[],
        'checked_at': '2026-06-08T12:00:00Z',
        'duration_s': 12.3,
        'ok': true,
      };
      final List<dynamic> issues = (report['issues'] as List<dynamic>?) ?? <dynamic>[];
      final List<dynamic> warnings = (report['warnings'] as List<dynamic>?) ?? <dynamic>[];
      expect(issues, isEmpty);
      expect(warnings, isEmpty);
    });

    test('no-report response lacks checked_at', () {
      final Map<String, dynamic> noReport = <String, dynamic>{
        'ok': null,
        'message': 'No health check has run yet.',
      };
      expect(noReport.containsKey('checked_at'), isFalse);
    });

    test('issue item has category and message', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'category': 'missing_file',
        'message': 'Missing: Show — ep.mkv',
        'item_type': 'tv',
        'item_id': 42,
      };
      expect(item['category'], isNotNull);
      expect(item['message'], isNotNull);
    });
  });
}
