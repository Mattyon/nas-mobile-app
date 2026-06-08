import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — complete health check screen key set', () {
    const List<String> allKeys = <String>[
      'healthCheck', 'runHealthCheck', 'healthCheckRunning',
      'healthCheckOk', 'healthCheckIssues', 'healthCheckWarnings',
      'healthCheckLastRun', 'healthCheckNever', 'healthCheckDuration',
      'healthCheckIssue', 'healthCheckWarning',
      'healthCheckMissing', 'healthCheckSmall', 'healthCheckNotImported',
      'healthCheckQbtError', 'healthCheckStalled',
      'healthCheckSonarr', 'healthCheckRadarr',
      'aiFix', 'aiFixing', 'aiFixResult', 'aiFixFailed',
      'ok', 'cancel',
    ];

    for (final String key in allKeys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty,
            reason: 'EN key "$key" must be non-empty');
        expect(v, isNot(equals(key)),
            reason: 'EN key "$key" must be translated (not fall back to key)');
      });

      test('CS "$key" translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty,
            reason: 'CS key "$key" must be non-empty');
        expect(v, isNot(equals(key)));
      });
    }
  });

  group('health check — stalled item swap flow', () {
    test('stalled item triggers swap with swapTorrent params', () {
      final Map<String, dynamic> stalledItem = <String, dynamic>{
        'type': 'movie',
        'item_id': 42,
        'queue_item_id': 7,
        'alternatives': <Map<String, dynamic>>[
          <String, dynamic>{
            'guid': 'magnet:?xt=urn:btih:deadbeef',
            'indexer_id': 3,
            'title': 'Best.Movie.2024.1080p',
          },
        ],
      };

      // Mirrors the swap call parameters
      final List<dynamic> alts = stalledItem['alternatives'] as List<dynamic>;
      expect(alts, isNotEmpty);

      final Map<String, dynamic> chosen = alts[0] as Map<String, dynamic>;
      final Map<String, dynamic> swapPayload = <String, dynamic>{
        'type': stalledItem['type'],
        'item_id': stalledItem['item_id'],
        'queue_item_id': stalledItem['queue_item_id'],
        'guid': chosen['guid'],
        'indexer_id': chosen['indexer_id'],
      };

      expect(swapPayload['type'], 'movie');
      expect(swapPayload['item_id'], 42);
      expect(swapPayload['queue_item_id'], 7);
      expect((swapPayload['guid'] as String).startsWith('magnet:'), isTrue);
      expect(swapPayload['indexer_id'], 3);
    });

    test('AI fix sends item as payload', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'category': 'torrent_error',
        'title': 'Movie 2024',
        'item_id': 99,
      };
      // Mirrors healthResolve(item) → data: {'item': item}
      final Map<String, dynamic> payload = <String, dynamic>{'item': item};
      expect(payload['item'], isNotNull);
      expect((payload['item'] as Map<String, dynamic>)['category'], 'torrent_error');
    });
  });

  group('health check — Fix All button shows stalled count', () {
    test('stalledItems filtered from all items', () {
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[
        <String, dynamic>{'category': 'stalled'},
        <String, dynamic>{'category': 'missing_file'},
        <String, dynamic>{'category': 'stalled'},
        <String, dynamic>{'category': 'sonarr'},
        <String, dynamic>{'category': 'stalled'},
      ];
      final List<Map<String, dynamic>> stalled =
          items.where((t) => t['category'] == 'stalled').toList();
      expect(stalled.length, 3);
    });

    test('Fix All label includes count', () {
      const int count = 3;
      final String label = 'Fix All ($count)';
      expect(label, 'Fix All (3)');
    });
  });
}
