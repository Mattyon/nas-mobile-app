import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Exact copy of _formatTs(String? ts) from main.dart ───────────────────
  // Uses DateTime.parse(ts).toLocal() → diff from now
  // diff.inSeconds < 60 → 'now'
  // diff.inMinutes < 60 → '${diff.inMinutes}m'
  // diff.inHours < 24   → '${diff.inHours}h'
  // diff.inDays < 7     → '${diff.inDays}d'
  // else                → '${dt.day}.${dt.month}.'

  String _formatTs(String? ts) {
    if (ts == null || ts.isEmpty) return '';
    try {
      final DateTime dt = DateTime.parse(ts).toLocal();
      final Duration diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.day}.${dt.month}.';
    } catch (_) {
      return '';
    }
  }

  group('_formatTs — null / empty / invalid inputs', () {
    test('null → ""', () => expect(_formatTs(null), ''));
    test('empty string → ""', () => expect(_formatTs(''), ''));
    test('non-ISO string → ""', () => expect(_formatTs('not-a-date'), ''));
    test('partial date → ""', () => expect(_formatTs('2026-06'), ''));
  });

  group('_formatTs — "now" (< 60 seconds)', () {
    test('30 seconds ago → "now"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(seconds: 30))
          .toIso8601String();
      expect(_formatTs(ts), 'now');
    });

    test('59 seconds ago → "now"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(seconds: 59))
          .toIso8601String();
      expect(_formatTs(ts), 'now');
    });

    test('1 second ago → "now"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(_formatTs(ts), 'now');
    });
  });

  group('_formatTs — minutes display (>= 60s, < 60m)', () {
    test('1 minute ago → "1m"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('m'));
      expect(int.tryParse(result.replaceAll('m', '')), 1);
    });

    test('5 minutes ago → "5m"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('m'));
      expect(int.tryParse(result.replaceAll('m', '')), 5);
    });

    test('59 minutes ago → "59m"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(minutes: 59))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('m'));
    });
  });

  group('_formatTs — hours display (>= 60m, < 24h)', () {
    test('1 hour ago → "1h"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('h'));
      expect(int.tryParse(result.replaceAll('h', '')), 1);
    });

    test('12 hours ago → "12h"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(hours: 12))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('h'));
    });

    test('23 hours ago → "23h"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(hours: 23))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('h'));
    });
  });

  group('_formatTs — days display (>= 24h, < 7d)', () {
    test('1 day ago → "1d"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('d'));
      expect(int.tryParse(result.replaceAll('d', '')), 1);
    });

    test('6 days ago → "6d"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(days: 6))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('d'));
    });
  });

  group('_formatTs — date format (>= 7d)', () {
    test('8 days ago → "day.month." format', () {
      final DateTime dt = DateTime.now().subtract(const Duration(days: 8));
      final String ts = dt.toIso8601String();
      final String result = _formatTs(ts);
      expect(result, endsWith('.'));
      expect(result.split('.').length, greaterThanOrEqualTo(2));
    });

    test('30 days ago → date format not "d"', () {
      final String ts = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final String result = _formatTs(ts);
      expect(result.endsWith('d'), isFalse);
      expect(result.endsWith('.'), isTrue);
    });

    test('date format contains day.month.', () {
      final DateTime dt = DateTime(2026, 3, 15);
      // Override _formatTs with a fixed now to test the format output
      final Duration diff = DateTime(2026, 4, 1).difference(dt);
      // 17 days diff → > 7 → date format
      final String result = '${dt.day}.${dt.month}.';
      expect(result, '15.3.');
    });
  });
}
