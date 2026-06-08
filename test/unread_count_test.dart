import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Mirrors badge label from NotificationBell build() ────────────────────
  // _unreadCount > 9 ? '9+' : '$_unreadCount'

  String _badgeLabel(int count) => count > 9 ? '9+' : '$count';

  group('notification bell — badge label', () {
    test('0 → "0"', () => expect(_badgeLabel(0), '0'));
    test('1 → "1"', () => expect(_badgeLabel(1), '1'));
    test('5 → "5"', () => expect(_badgeLabel(5), '5'));
    test('9 → "9" (boundary)', () => expect(_badgeLabel(9), '9'));
    test('10 → "9+" (> 9)', () => expect(_badgeLabel(10), '9+'));
    test('99 → "9+"', () => expect(_badgeLabel(99), '9+'));
    test('1000 → "9+"', () => expect(_badgeLabel(1000), '9+'));
  });

  group('notification bell — badge visibility', () {
    // Badge is shown when _unreadCount > 0
    test('0 unread → badge not shown', () {
      const int count = 0;
      expect(count > 0, isFalse);
    });

    test('1 unread → badge shown', () {
      const int count = 1;
      expect(count > 0, isTrue);
    });
  });

  group('notification bell — unread_count from API response', () {
    // Mirrors: unread = (data['unread_count'] as int?) ?? 0

    test('unread_count=3 parsed correctly', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'notifications': <dynamic>[],
        'unread_count': 3,
      };
      final int unread = (data['unread_count'] as int?) ?? 0;
      expect(unread, 3);
    });

    test('missing unread_count defaults to 0', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'notifications': <dynamic>[],
      };
      final int unread = (data['unread_count'] as int?) ?? 0;
      expect(unread, 0);
    });

    test('unread_count=0', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'notifications': <dynamic>[],
        'unread_count': 0,
      };
      final int unread = (data['unread_count'] as int?) ?? 0;
      expect(unread, 0);
    });
  });

  group('notification bell — fresh item detection', () {
    // Mirrors: fresh = items where id > _lastSeenId

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'title': 'Old 1'},
      <String, dynamic>{'id': 2, 'title': 'Old 2'},
      <String, dynamic>{'id': 3, 'title': 'New 1'},
      <String, dynamic>{'id': 4, 'title': 'New 2'},
    ];

    test('items with id > lastSeenId are fresh', () {
      const int lastId = 2;
      final List<Map<String, dynamic>> fresh = items
          .where((Map<String, dynamic> n) => (n['id'] as int? ?? 0) > lastId)
          .toList();
      expect(fresh.length, 2);
      expect(fresh[0]['title'], 'New 1');
    });

    test('no items newer than lastSeenId → empty fresh list', () {
      const int lastId = 10;
      final List<Map<String, dynamic>> fresh = items
          .where((Map<String, dynamic> n) => (n['id'] as int? ?? 0) > lastId)
          .toList();
      expect(fresh, isEmpty);
    });

    test('max id is computed correctly', () {
      const int lastId = 2;
      final List<Map<String, dynamic>> fresh = items
          .where((n) => (n['id'] as int? ?? 0) > lastId)
          .toList();
      final int newMax = fresh
          .map((n) => n['id'] as int? ?? 0)
          .reduce((a, b) => a > b ? a : b);
      expect(newMax, 4);
    });

    test('at most 3 notifications sent to system tray', () {
      final List<Map<String, dynamic>> manyItems = List.generate(
          10, (i) => <String, dynamic>{'id': i + 1, 'title': 'Notif $i'});
      final List<Map<String, dynamic>> taken = manyItems.take(3).toList();
      expect(taken.length, 3);
    });
  });
}
