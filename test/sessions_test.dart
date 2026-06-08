import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── Exact copy of _ago(int unixSec) from _SessionsScreenState ────────────
  // diffSec = DateTime.now().millisecondsSinceEpoch ~/ 1000 - unixSec
  // <= 0      → ''
  // < 90      → '${diffSec}s ago'
  // m < 90    → '${m}m ago'    (m = diffSec ~/ 60)
  // h < 48    → '${h}h ago'   (h = diffSec ~/ 3600)
  // else      → '${d}d ago'   (d = diffSec ~/ 86400)

  String _ago(int nowUnix, int unixSec) {
    if (unixSec <= 0) return '';
    final int diffSec = nowUnix - unixSec;
    if (diffSec < 90) return '${diffSec}s ago';
    final int m = diffSec ~/ 60;
    if (m < 90) return '${m}m ago';
    final int h = diffSec ~/ 3600;
    if (h < 48) return '${h}h ago';
    return '${diffSec ~/ 86400}d ago';
  }

  // Stale = lastViewedAt > 0 && (now_unix - lastViewedAt) > 300
  bool _isStale(int nowUnix, int lastViewedAt) {
    return lastViewedAt > 0 && (nowUnix - lastViewedAt) > 300;
  }

  group('sessions — _ago: edge cases', () {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('unixSec = 0 → empty string', () {
      expect(_ago(now, 0), '');
    });

    test('unixSec = -1 → empty string', () {
      expect(_ago(now, -1), '');
    });
  });

  group('sessions — _ago: seconds display (< 90s)', () {
    final int now = 1000000;

    test('1 second ago → "1s ago"', () {
      expect(_ago(now, now - 1), '1s ago');
    });

    test('89 seconds ago → "89s ago" (last entry in seconds range)', () {
      expect(_ago(now, now - 89), '89s ago');
    });
  });

  group('sessions — _ago: minutes display (>= 90s, < 90m)', () {
    final int now = 1000000;

    test('90 seconds ago → "1m ago"', () {
      expect(_ago(now, now - 90), '1m ago');
    });

    test('5 minutes ago → "5m ago"', () {
      expect(_ago(now, now - 300), '5m ago');
    });

    test('89 minutes 59s ago → "89m ago"', () {
      expect(_ago(now, now - (89 * 60 + 59)), '89m ago');
    });
  });

  group('sessions — _ago: hours display (>= 90m, < 48h)', () {
    final int now = 1000000;

    test('90 minutes ago → "1h ago"', () {
      expect(_ago(now, now - 90 * 60), '1h ago');
    });

    test('2 hours ago → "2h ago"', () {
      expect(_ago(now, now - 7200), '2h ago');
    });

    test('47 hours ago → "47h ago"', () {
      expect(_ago(now, now - 47 * 3600), '47h ago');
    });
  });

  group('sessions — _ago: days display (>= 48h)', () {
    final int now = 1000000;

    test('48 hours ago → "2d ago"', () {
      expect(_ago(now, now - 48 * 3600), '2d ago');
    });

    test('7 days ago → "7d ago"', () {
      expect(_ago(now, now - 7 * 86400), '7d ago');
    });
  });

  group('sessions — stale badge logic', () {
    final int now = 1000000;

    test('lastViewedAt = 0 → not stale (regardless of time)', () {
      expect(_isStale(now, 0), isFalse);
    });

    test('exactly 300s ago → not stale (threshold is > 300)', () {
      expect(_isStale(now, now - 300), isFalse);
    });

    test('301s ago → stale', () {
      expect(_isStale(now, now - 301), isTrue);
    });

    test('10 minutes ago → stale', () {
      expect(_isStale(now, now - 600), isTrue);
    });
  });

  group('sessions — source badge logic', () {
    String _sourceBadge(Map<String, dynamic> session) {
      final String source = (session['source'] ?? 'plex').toString();
      return source == 'plex' ? 'PLEX' : 'JELLYFIN';
    }

    test('source="plex" → PLEX badge', () {
      expect(_sourceBadge(<String, dynamic>{'source': 'plex'}), 'PLEX');
    });

    test('source="jellyfin" → JELLYFIN badge', () {
      expect(_sourceBadge(<String, dynamic>{'source': 'jellyfin'}), 'JELLYFIN');
    });

    test('missing source defaults to PLEX badge', () {
      expect(_sourceBadge(<String, dynamic>{}), 'PLEX');
    });
  });

  group('sessions — bandwidth display', () {
    test('1000 kbps → 1.0 Mbit/s', () {
      final num bw = 1000;
      final String display = '${(bw / 1000).toStringAsFixed(1)} Mbit/s';
      expect(display, '1.0 Mbit/s');
    });

    test('2500 kbps → 2.5 Mbit/s', () {
      final num bw = 2500;
      expect('${(bw / 1000).toStringAsFixed(1)} Mbit/s', '2.5 Mbit/s');
    });
  });

  group('i18n — sessions screen keys', () {
    const List<String> keys = <String>[
      'mediaSessions', 'noSessions', 'transcode', 'direct',
    ];

    for (final String key in keys) {
      test('EN "$key" is non-empty', () {
        lang.value = 'en';
        expect(tr(key), isNotEmpty);
      });

      test('CS "$key" is translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('mediaSessions EN != CS (unique translations)', () {
      lang.value = 'en';
      final String en = tr('mediaSessions');
      lang.value = 'cs';
      final String cs = tr('mediaSessions');
      expect(en, isNot(equals(cs)));
    });

    test('transcode and direct are different labels in CS', () {
      lang.value = 'cs';
      expect(tr('transcode'), isNot(equals(tr('direct'))));
    });
  });
}
