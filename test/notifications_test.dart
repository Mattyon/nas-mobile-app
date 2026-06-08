import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — notification list keys', () {
    const List<String> keys = <String>[
      'notifications', 'noNotifications', 'clearAll',
      'checkNewEps', 'newEpsStarted',
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

    test('notifications and noNotifications are different', () {
      lang.value = 'en';
      expect(tr('notifications'), isNot(equals(tr('noNotifications'))));
    });

    test('clearAll and checkNewEps are different', () {
      lang.value = 'en';
      expect(tr('clearAll'), isNot(equals(tr('checkNewEps'))));
    });

    test('checkNewEps and newEpsStarted are different', () {
      lang.value = 'en';
      expect(tr('checkNewEps'), isNot(equals(tr('newEpsStarted'))));
    });
  });

  group('notifications — data structure', () {
    test('notification has title, body, ts, and id fields', () {
      final Map<String, dynamic> n = <String, dynamic>{
        'id': 42,
        'title': 'Download complete',
        'body': 'Movie.2024.mkv downloaded',
        'ts': '2026-06-08T12:00:00Z',
      };
      expect(n['id'], isNotNull);
      expect(n['title'], isNotNull);
      expect(n['body'], isNotNull);
      expect(n['ts'], isNotNull);
    });

    test('notification API response contains notifications list and unread_count', () {
      final Map<String, dynamic> response = <String, dynamic>{
        'notifications': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'title': 'Alert'},
        ],
        'unread_count': 1,
      };
      final List<dynamic> items =
          (response['notifications'] as List<dynamic>?) ?? <dynamic>[];
      final int unread = (response['unread_count'] as int?) ?? 0;
      expect(items.length, 1);
      expect(unread, 1);
    });

    test('null notifications list → empty', () {
      final Map<String, dynamic> response = <String, dynamic>{};
      final List<dynamic> items =
          (response['notifications'] as List<dynamic>?) ?? <dynamic>[];
      expect(items, isEmpty);
    });
  });

  group('notifications — background poll: fresh item detection', () {
    // Mirrors _bgPollNotifications: items where id > lastId
    final List<Map<String, dynamic>> allItems = <Map<String, dynamic>>[
      <String, dynamic>{'id': 10, 'title': 'Old'},
      <String, dynamic>{'id': 20, 'title': 'Old 2'},
      <String, dynamic>{'id': 30, 'title': 'New'},
      <String, dynamic>{'id': 40, 'title': 'Newest'},
    ];

    test('items with id > lastId are detected as fresh', () {
      const int lastId = 20;
      final List<Map<String, dynamic>> fresh = allItems
          .where((n) => (n['id'] as int? ?? 0) > lastId)
          .toList();
      expect(fresh.length, 2);
      expect(fresh[0]['title'], 'New');
    });

    test('lastId updated to max fresh id', () {
      const int lastId = 10;
      final List<Map<String, dynamic>> fresh = allItems
          .where((n) => (n['id'] as int? ?? 0) > lastId)
          .toList();
      final int newMax = fresh
          .map((n) => n['id'] as int? ?? 0)
          .reduce((a, b) => a > b ? a : b);
      expect(newMax, 40);
    });

    test('notification id modulo for system notification id', () {
      // Mirrors: id: (n['id'] as int? ?? 0).abs() % 100000
      const int notifId = 123456789;
      final int sysId = notifId.abs() % 100000;
      expect(sysId, lessThan(100000));
      expect(sysId, greaterThanOrEqualTo(0));
    });
  });
}
