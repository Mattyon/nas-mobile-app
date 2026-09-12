import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // Download subtitle labels must be translated (not left as raw English) in
  // both languages — the "Downloading"/"ETA" bug was these being hardcoded.
  const List<String> keys = <String>[
    'eta', 'ratio',
    'stateDownloading', 'stateStalledNoPeers', 'stateFetchingMetadata',
    'stateChecking', 'stateAllocating', 'stateQueued', 'statePaused',
    'stateStopped', 'stateSeeding', 'stateSeedingStalled', 'stateError',
    'stateMissingFiles', 'stateMoving', 'stateUnknown',
  ];

  group('i18n — download state labels', () {
    for (final String key in keys) {
      test('EN "$key" present', () {
        lang.value = 'en';
        expect(tr(key), isNot(equals(key)));
        expect(tr(key), isNotEmpty);
      });
      test('CS "$key" present and differs from EN where expected', () {
        lang.value = 'en';
        final String en = tr(key);
        lang.value = 'cs';
        final String cs = tr(key);
        expect(cs, isNot(equals(key)));
        expect(cs, isNotEmpty);
        // 'eta'/'ratio' etc. get real Czech words; assert the states did too.
        if (key.startsWith('state')) {
          expect(cs, isNot(equals(en)),
              reason: '$key should have a distinct Czech translation');
        }
      });
    }

    test('key semantics: Downloading -> Stahuje se, ETA -> Odhad', () {
      lang.value = 'cs';
      expect(tr('stateDownloading'), 'Stahuje se');
      expect(tr('eta'), 'Odhad');
      lang.value = 'en';
      expect(tr('stateDownloading'), 'Downloading');
      expect(tr('eta'), 'ETA');
    });
  });
}
