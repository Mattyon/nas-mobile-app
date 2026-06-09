import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  const List<String> _cameraKeys = <String>[
    'cameraFeed', 'cameras', 'noCameras', 'addCamera',
    'cameraName', 'cameraUrl', 'cameraDelete', 'cameraDeleteConfirm',
  ];

  group('i18n — camera keys', () {
    for (final String key in _cameraKeys) {
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
  });
}
