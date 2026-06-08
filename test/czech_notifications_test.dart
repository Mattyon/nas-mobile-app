import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── Bilingual display logic (exact from _NotificationBellState) ───────────
  String _displayTitle(Map<String, dynamic> n, String language) {
    final bool cs = language == 'cs';
    return cs
        ? (n['title_cs']?.toString() ?? n['title']?.toString() ?? '')
        : (n['title']?.toString() ?? '');
  }

  String _displayBody(Map<String, dynamic> n, String language) {
    final bool cs = language == 'cs';
    return cs
        ? (n['body_cs']?.toString() ?? n['body']?.toString() ?? '')
        : (n['body']?.toString() ?? '');
  }

  group('notifications — bilingual title display', () {
    final Map<String, dynamic> n = <String, dynamic>{
      'title': 'Download complete',
      'title_cs': 'Stahování dokončeno',
      'body': 'Movie.mkv ready',
      'body_cs': 'Film.mkv připraven',
    };

    test('EN language → English title', () {
      expect(_displayTitle(n, 'en'), 'Download complete');
    });

    test('CS language → Czech title', () {
      expect(_displayTitle(n, 'cs'), 'Stahování dokončeno');
    });

    test('EN language → English body', () {
      expect(_displayBody(n, 'en'), 'Movie.mkv ready');
    });

    test('CS language → Czech body', () {
      expect(_displayBody(n, 'cs'), 'Film.mkv připraven');
    });
  });

  group('notifications — CS fallback to EN when no Czech translation', () {
    final Map<String, dynamic> nNoCs = <String, dynamic>{
      'title': 'Alert',
      'body': 'Something happened',
      // no title_cs or body_cs
    };

    test('CS title falls back to EN title', () {
      expect(_displayTitle(nNoCs, 'cs'), 'Alert');
    });

    test('CS body falls back to EN body', () {
      expect(_displayBody(nNoCs, 'cs'), 'Something happened');
    });
  });

  group('notifications — empty notification', () {
    final Map<String, dynamic> empty = <String, dynamic>{};

    test('EN empty → empty title', () => expect(_displayTitle(empty, 'en'), ''));
    test('EN empty → empty body', () => expect(_displayBody(empty, 'en'), ''));
    test('CS empty → empty title', () => expect(_displayTitle(empty, 'cs'), ''));
    test('CS empty → empty body', () => expect(_displayBody(empty, 'cs'), ''));
  });

  group('notifications — null field handling', () {
    final Map<String, dynamic> n = <String, dynamic>{
      'title': null,
      'body': null,
    };

    test('null title → empty string in EN', () {
      expect(_displayTitle(n, 'en'), '');
    });

    test('null body → empty string in EN', () {
      expect(_displayBody(n, 'en'), '');
    });
  });

  group('i18n — notification screen keys', () {
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
  });
}
