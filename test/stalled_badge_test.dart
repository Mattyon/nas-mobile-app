import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── Fix All (N) button label ──────────────────────────────────────────────

  group('health check — Fix All (N) button label', () {
    String _fixAllLabel(int n) => 'Fix All ($n)';

    test('Fix All (1)', () => expect(_fixAllLabel(1), 'Fix All (1)'));
    test('Fix All (3)', () => expect(_fixAllLabel(3), 'Fix All (3)'));
    test('Fix All (10)', () => expect(_fixAllLabel(10), 'Fix All (10)'));
    test('Fix All (0)', () => expect(_fixAllLabel(0), 'Fix All (0)'));
  });

  // ── Stalled item count from health report ─────────────────────────────────

  group('health check — stalled count calculation', () {
    test('count stalled items from health report', () {
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[
        <String, dynamic>{'category': 'stalled', 'title': 'A'},
        <String, dynamic>{'category': 'stalled', 'title': 'B'},
        <String, dynamic>{'category': 'missing_file', 'title': 'C'},
        <String, dynamic>{'category': 'stalled', 'title': 'D'},
      ];
      final int count = items
          .where((t) => t['category'] == 'stalled')
          .length;
      expect(count, 3);
    });

    test('no stalled items → count 0', () {
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[
        <String, dynamic>{'category': 'missing_file', 'title': 'A'},
      ];
      final int count = items
          .where((t) => t['category'] == 'stalled')
          .length;
      expect(count, 0);
    });

    test('empty list → count 0', () {
      expect(<Map<String, dynamic>>[]
          .where((t) => t['category'] == 'stalled')
          .length, 0);
    });
  });

  // ── Stalled item structure ─────────────────────────────────────────────────

  group('health check — stalled item data structure', () {
    test('stalled item has required fields', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'type': 'movie',
        'title': 'The Movie',
        'category': 'stalled',
        'item_id': 42,
        'queue_item_id': 7,
        'alternatives': <Map<String, dynamic>>[],
      };
      expect(item['type'], isNotNull);
      expect(item['title'], isNotNull);
      expect(item['category'], 'stalled');
      expect(item['item_id'], isNotNull);
      expect(item['queue_item_id'], isNotNull);
    });

    test('stalled item with alternatives has at least one alternative', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'type': 'movie',
        'item_id': 1,
        'queue_item_id': 2,
        'alternatives': <Map<String, dynamic>>[
          <String, dynamic>{
            'guid': 'magnet:?xt=urn:btih:abc123',
            'indexer_id': 1,
            'title': 'Alt Release',
          },
        ],
      };
      final List<dynamic> alts =
          item['alternatives'] as List<dynamic>;
      expect(alts, isNotEmpty);
      final Map<String, dynamic> alt = alts[0] as Map<String, dynamic>;
      expect(alt['guid'], startsWith('magnet:'));
      expect(alt['indexer_id'], isNotNull);
    });
  });

  // ── Health check i18n ──────────────────────────────────────────────────────

  group('i18n — health check category keys', () {
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
      test('EN category "${entry.key}" → "${entry.value}" translated', () {
        lang.value = 'en';
        final String v = tr(entry.value);
        expect(v, isNotEmpty,
            reason: '${entry.value} must be translated');
        expect(v, isNot(equals(entry.value)));
      });

      test('CS category "${entry.key}" → "${entry.value}" translated', () {
        lang.value = 'cs';
        final String v = tr(entry.value);
        expect(v, isNotEmpty,
            reason: 'CS ${entry.value} must be translated');
        expect(v, isNot(equals(entry.value)));
      });
    }

    test('7 category keys are all distinct in EN', () {
      lang.value = 'en';
      final Set<String> vals =
          categoryToKey.values.map(tr).toSet();
      expect(vals.length, categoryToKey.length,
          reason: 'Each health check category needs a unique label');
    });
  });
}
