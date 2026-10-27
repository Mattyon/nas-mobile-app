import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/notification_filter.dart';

Map<String, dynamic> release(String v) =>
    <String, dynamic>{'event': 'app.release', 'body': 'Version $v is available — update in Google Play.'};

void main() {
  test('a notice for the installed version is dropped', () {
    expect(alreadyInstalled(release('1.1.8'), '1.1.8'), isTrue);
    expect(alreadyInstalled(release('1.1.8'), '1.1.9'), isTrue);
  });

  test('a newer version is still announced', () {
    expect(alreadyInstalled(release('1.1.9'), '1.1.8'), isFalse);
    expect(alreadyInstalled(release('1.2.0'), '1.1.10'), isFalse);
  });

  test('versions compare as numbers, not text', () {
    expect(alreadyInstalled(release('1.1.10'), '1.1.9'), isFalse);
  });

  test('dev builds and other notifications are never dropped', () {
    expect(alreadyInstalled(release('1.1.8'), 'dev'), isFalse);
    expect(alreadyInstalled(<String, dynamic>{'event': 'download.done', 'body': 'Version 1.1.8'}, '1.1.8'), isFalse);
  });
}
