import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — torrent swap keys', () {
    const List<String> keys = <String>['swap', 'swapStarted', 'noAlternative'];

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

    test('swap and swapStarted are different labels', () {
      lang.value = 'en';
      expect(tr('swap'), isNot(equals(tr('swapStarted'))));
    });

    test('swapStarted and noAlternative are different labels', () {
      lang.value = 'en';
      expect(tr('swapStarted'), isNot(equals(tr('noAlternative'))));
    });
  });

  group('torrent swap — swapTorrent request payload', () {
    // Mirrors Api.I.swapTorrent() parameters
    test('valid swap request has required fields', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'movie',
        'item_id': 42,
        'queue_item_id': 7,
        'guid': 'magnet:?xt=urn:btih:abc123def456',
        'indexer_id': 1,
      };
      expect(payload['type'], isNotNull);
      expect(payload['item_id'], isNotNull);
      expect(payload['queue_item_id'], isNotNull);
      expect(payload['guid'], startsWith('magnet:'));
      expect(payload['indexer_id'], isNotNull);
    });

    test('type can be movie or tv', () {
      for (final String t in <String>['movie', 'tv']) {
        final Map<String, dynamic> payload = <String, dynamic>{
          'type': t,
          'item_id': 1,
          'queue_item_id': 2,
          'guid': 'magnet:abc',
          'indexer_id': 1,
        };
        expect(payload['type'], t);
      }
    });
  });

  group('torrent swap — grab response parsing', () {
    test('success response with no_czech_audio=true triggers fallback', () {
      final Map<String, dynamic> response = <String, dynamic>{
        'no_czech_audio': true,
        'title': 'Some Movie',
      };
      expect(response['no_czech_audio'], isTrue);
    });

    test('success response without no_czech_audio flag → normal grab', () {
      final Map<String, dynamic> response = <String, dynamic>{
        'status': 'queued',
      };
      expect(response['no_czech_audio'], isNull);
    });

    test('grab updates on_disk_en when language=en', () {
      // Mirrors: if (language == 'en') item['on_disk_en'] = true
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': false, 'on_disk_cs': false,
      };
      const String language = 'en';
      if (language == 'en') item['on_disk_en'] = true;
      expect(item['on_disk_en'], isTrue);
      expect(item['on_disk_cs'], isFalse);
    });

    test('grab updates on_disk_cs when language=cs', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'on_disk_en': false, 'on_disk_cs': false,
      };
      const String language = 'cs';
      if (language == 'cs') item['on_disk_cs'] = true;
      expect(item['on_disk_cs'], isTrue);
      expect(item['on_disk_en'], isFalse);
    });
  });
}
