// In a browser dio counts the connect timeout until the response headers arrive, so on
// the web version every slow endpoint (/speedtest, AI chat, grabs) failed after 15 s.
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';

void main() {
  test('web: no separate connect timeout, the receive timeout is the limit', () {
    expect(connectTimeoutFor(web: true), isNull);
  });

  test('Android keeps its 15 s connect timeout', () {
    expect(connectTimeoutFor(web: false), const Duration(seconds: 15));
  });
}
