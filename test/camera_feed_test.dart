import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — cameraFeed key', () {
    test('EN cameraFeed is translated', () {
      lang.value = 'en';
      final String v = tr('cameraFeed');
      expect(v, isNotEmpty);
      expect(v, isNot(equals('cameraFeed')));
    });

    test('CS cameraFeed is translated', () {
      lang.value = 'cs';
      final String v = tr('cameraFeed');
      expect(v, isNotEmpty);
      expect(v, isNot(equals('cameraFeed')));
    });
  });
}
