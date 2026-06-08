import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── Exact logic from _SearchScreenState._buildTrailing() ─────────────────
  // hasEn = item['on_disk_en'] == true
  // hasCs = item['on_disk_cs'] == true
  // inLibrary = hasEn && hasCs → show chips + "In library" (NO download button)
  // hasEn || hasCs (not both) → show chips + download button
  // neither → download button only

  bool _hasEn(Map<String, dynamic> item) => item['on_disk_en'] == true;
  bool _hasCs(Map<String, dynamic> item) => item['on_disk_cs'] == true;
  bool _inLibrary(Map<String, dynamic> item) =>
      _hasEn(item) && _hasCs(item);
  bool _showDownloadBtn(Map<String, dynamic> item) =>
      !_inLibrary(item);
  bool _showChips(Map<String, dynamic> item) =>
      _hasEn(item) || _hasCs(item);

  // ── _buildTrailing state machine ──────────────────────────────────────────

  group('search — trailing: in-library state (both EN and CS on disk)', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'on_disk_en': true, 'on_disk_cs': true,
    };

    test('inLibrary flag is true', () => expect(_inLibrary(item), isTrue));
    test('no download button shown', () => expect(_showDownloadBtn(item), isFalse));
    test('chips are shown (both flags)', () => expect(_showChips(item), isTrue));
  });

  group('search — trailing: EN-only on disk', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'on_disk_en': true, 'on_disk_cs': false,
    };

    test('inLibrary is false', () => expect(_inLibrary(item), isFalse));
    test('download button shown', () => expect(_showDownloadBtn(item), isTrue));
    test('EN chip shown', () => expect(_hasEn(item), isTrue));
    test('CS chip not shown', () => expect(_hasCs(item), isFalse));
    test('chips row shown (at least one language)', () =>
        expect(_showChips(item), isTrue));
  });

  group('search — trailing: CS-only on disk', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'on_disk_en': false, 'on_disk_cs': true,
    };

    test('inLibrary is false', () => expect(_inLibrary(item), isFalse));
    test('download button shown', () => expect(_showDownloadBtn(item), isTrue));
    test('EN chip not shown', () => expect(_hasEn(item), isFalse));
    test('CS chip shown', () => expect(_hasCs(item), isTrue));
  });

  group('search — trailing: not on disk at all', () {
    final Map<String, dynamic> item = <String, dynamic>{
      'on_disk_en': false, 'on_disk_cs': false,
    };

    test('inLibrary is false', () => expect(_inLibrary(item), isFalse));
    test('download button shown', () => expect(_showDownloadBtn(item), isTrue));
    test('no chips shown', () => expect(_showChips(item), isFalse));
  });

  group('search — trailing: null flags treated as not on disk', () {
    final Map<String, dynamic> item = <String, dynamic>{};

    test('hasEn → false', () => expect(_hasEn(item), isFalse));
    test('hasCs → false', () => expect(_hasCs(item), isFalse));
    test('inLibrary → false', () => expect(_inLibrary(item), isFalse));
    test('showDownloadBtn → true', () => expect(_showDownloadBtn(item), isTrue));
  });

  // ── _key() generation ─────────────────────────────────────────────────────

  group('search — item key generation', () {
    // Mirrors: '${m['type']}-${m['tmdbId'] ?? m['tvdbId']}'
    String key(Map<String, dynamic> m) =>
        '${m['type']}-${m['tmdbId'] ?? m['tvdbId']}';

    test('movie with tmdbId → "movie-12345"', () {
      expect(key(<String, dynamic>{'type': 'movie', 'tmdbId': 12345}),
          'movie-12345');
    });

    test('TV with tvdbId only → "tv-67890"', () {
      expect(key(<String, dynamic>{'type': 'tv', 'tvdbId': 67890}), 'tv-67890');
    });

    test('TV prefers tmdbId when both present', () {
      expect(
          key(<String, dynamic>{'type': 'tv', 'tmdbId': 111, 'tvdbId': 222}),
          'tv-111');
    });

    test('movie and tv with same id produce different keys', () {
      final String m = key(<String, dynamic>{'type': 'movie', 'tmdbId': 100});
      final String t = key(<String, dynamic>{'type': 'tv', 'tmdbId': 100});
      expect(m, isNot(equals(t)));
    });
  });

  // ── Stage loading i18n keys ───────────────────────────────────────────────

  group('search — stage loading keys', () {
    const List<String> stages = <String>[
      'stageSearch', 'stageDatabases', 'stagePick', 'stageStart',
    ];

    for (final String key in stages) {
      test('EN "$key" translated and non-empty', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
      test('CS "$key" translated and non-empty', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('all 4 stage keys have distinct EN values', () {
      lang.value = 'en';
      final Set<String> vals = stages.map(tr).toSet();
      expect(vals.length, stages.length,
          reason: 'All stage messages must be unique');
    });

    test('all 4 stage keys have distinct CS values', () {
      lang.value = 'cs';
      final Set<String> vals = stages.map(tr).toSet();
      expect(vals.length, stages.length);
    });
  });

  // ── Czech audio fallback message ──────────────────────────────────────────

  group('search — Czech audio fallback dialog', () {
    test('EN noCzechAudioMsg contains {title} and {tier} placeholders', () {
      lang.value = 'en';
      final String msg = tr('noCzechAudioMsg');
      expect(msg.contains('{title}'), isTrue);
      expect(msg.contains('{tier}'), isTrue);
    });

    test('CS noCzechAudioMsg contains {title} placeholder', () {
      lang.value = 'cs';
      expect(tr('noCzechAudioMsg').contains('{title}'), isTrue);
    });

    test('interpolating {title} replaces the placeholder', () {
      lang.value = 'en';
      final String result = tr('noCzechAudioMsg')
          .replaceFirst('{title}', 'Inception')
          .replaceFirst('{tier}', 'balanced');
      expect(result.contains('{title}'), isFalse);
      expect(result.contains('{tier}'), isFalse);
      expect(result.contains('Inception'), isTrue);
    });
  });

  // ── Type badge i18n ───────────────────────────────────────────────────────

  group('search — type badge i18n', () {
    test('EN movie and tv labels are different', () {
      lang.value = 'en';
      expect(tr('movie'), isNot(equals(tr('tv'))));
    });

    test('CS movie and tv labels are different', () {
      lang.value = 'cs';
      expect(tr('movie'), isNot(equals(tr('tv'))));
    });

    test('quality tier fast/balanced/best all different', () {
      lang.value = 'en';
      final Set<String> tiers = {'fast', 'balanced', 'best'}.map(tr).toSet();
      expect(tiers.length, 3);
    });
  });
}
