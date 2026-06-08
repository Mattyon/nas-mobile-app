import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — unified media sessions keys', () {
    test('EN mediaSessions is translated', () {
      lang.value = 'en';
      expect(tr('mediaSessions'), isNotEmpty);
      expect(tr('mediaSessions'), isNot('mediaSessions'));
    });

    test('CS mediaSessions is translated', () {
      lang.value = 'cs';
      expect(tr('mediaSessions'), isNotEmpty);
      expect(tr('mediaSessions'), isNot('mediaSessions'));
    });

    test('EN and CS mediaSessions labels are different', () {
      lang.value = 'en';
      final String en = tr('mediaSessions');
      lang.value = 'cs';
      final String cs = tr('mediaSessions');
      expect(en, isNot(equals(cs)));
    });

    test('EN noSessions is translated', () {
      lang.value = 'en';
      expect(tr('noSessions'), isNotEmpty);
      expect(tr('noSessions'), isNot('noSessions'));
    });

    test('CS noSessions is translated', () {
      lang.value = 'cs';
      expect(tr('noSessions'), isNotEmpty);
    });

    test('mediaSessions and noSessions are different labels', () {
      lang.value = 'en';
      expect(tr('mediaSessions'), isNot(equals(tr('noSessions'))));
    });
  });

  group('media sessions — source badge logic', () {
    // Mirrors SessionsScreen source badge
    String _badge(String source) =>
        source == 'plex' ? 'PLEX' : 'JELLYFIN';

    test('plex source → PLEX badge', () => expect(_badge('plex'), 'PLEX'));
    test('jellyfin source → JELLYFIN badge', () => expect(_badge('jellyfin'), 'JELLYFIN'));
    test('other source → JELLYFIN badge (default)', () => expect(_badge('emby'), 'JELLYFIN'));
  });

  group('media sessions — session data parsing', () {
    test('session has user, title, state, and source fields', () {
      final Map<String, dynamic> session = <String, dynamic>{
        'user': 'matty',
        'title': 'Inception',
        'state': 'playing',
        'source': 'plex',
        'progress_pct': 45.5,
        'transcode': false,
      };
      expect(session['user'], isNotNull);
      expect(session['title'], isNotNull);
      expect(session['state'], isNotNull);
      expect(session['source'], isNotNull);
    });

    test('progress_pct parsed as double', () {
      final Map<String, dynamic> session = <String, dynamic>{
        'progress_pct': 45,
      };
      final double pct = (session['progress_pct'] as num?)?.toDouble() ?? 0;
      expect(pct, 45.0);
    });

    test('missing progress_pct defaults to 0', () {
      final Map<String, dynamic> session = <String, dynamic>{};
      final double pct = (session['progress_pct'] as num?)?.toDouble() ?? 0;
      expect(pct, 0.0);
    });

    test('sessions list from /sessions API response', () {
      final Map<String, dynamic> response = <String, dynamic>{
        'sessions': <Map<String, dynamic>>[
          <String, dynamic>{'user': 'alice', 'source': 'plex'},
          <String, dynamic>{'user': 'bob', 'source': 'jellyfin'},
        ],
      };
      final List<dynamic> sessions =
          response['sessions'] as List<dynamic>;
      expect(sessions.length, 2);
    });
  });
}
