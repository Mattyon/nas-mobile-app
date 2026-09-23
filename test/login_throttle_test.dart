import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';
import 'package:nas_app/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The gateway began answering `POST /login` with 429 on 2026-09-23, after five failed
/// attempts inside a minute from the same client. The app had never seen that status:
/// `_submit()` catches everything and shows "Login failed", so a throttled user would
/// read it as a wrong password and keep retrying — the one response that cannot
/// succeed. These tests pin the distinction, and the wait we tell them to make.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding installs an HttpOverrides that answers every request with 400 and
  // never opens a socket, which would make these tests assert on the binding rather
  // than on Api.login(). Dropping it restores real networking to the loopback server
  // below; nothing here reaches beyond 127.0.0.1.
  setUpAll(() => HttpOverrides.global = null);

  /// A stand-in gateway. Returns [status] for `POST /login`, with [retryAfter] as the
  /// Retry-After header when given.
  Future<HttpServer> serve(int status, {String? retryAfter}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      if (retryAfter != null) req.response.headers.set('Retry-After', retryAfter);
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(<String, String>{'detail': 'nope'}));
      await req.response.close();
    });
    return server;
  }

  Future<void> pointAppAt(HttpServer server) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Api.I.setBaseUrl('http://127.0.0.1:${server.port}');
  }

  group('login throttling', () {
    test('429 surfaces as LoginThrottled, not a generic failure', () async {
      final server = await serve(429, retryAfter: '42');
      await pointAppAt(server);
      await expectLater(
        Api.I.login('claude', 'wrong'),
        throwsA(isA<LoginThrottled>()
            .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 42)),
      );
      await server.close(force: true);
    });

    test('a missing Retry-After falls back to the gateway window', () async {
      final server = await serve(429);
      await pointAppAt(server);
      await expectLater(
        Api.I.login('claude', 'wrong'),
        throwsA(isA<LoginThrottled>()
            .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 60)),
      );
      await server.close(force: true);
    });

    test('an unparseable Retry-After falls back rather than throwing', () async {
      final server = await serve(429, retryAfter: 'Wed, 21 Oct 2026 07:28:00 GMT');
      await pointAppAt(server);
      await expectLater(
        Api.I.login('claude', 'wrong'),
        throwsA(isA<LoginThrottled>()
            .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 60)),
      );
      await server.close(force: true);
    });

    test('a wrong password is still an ordinary failure', () async {
      // 401 must NOT become LoginThrottled — the two need different messages.
      final server = await serve(401);
      await pointAppAt(server);
      await expectLater(
        Api.I.login('claude', 'wrong'),
        throwsA(allOf(isA<DioException>(), isNot(isA<LoginThrottled>()))),
      );
      await server.close(force: true);
    });
  });

  group('i18n — throttled login', () {
    for (final code in <String>['en', 'cs']) {
      test('$code string exists and carries the {s} slot', () {
        lang.value = code;
        final v = tr('loginThrottled');
        expect(v, isNotEmpty);
        expect(v, isNot(equals('loginThrottled')));
        expect(v.contains('{s}'), isTrue,
            reason: 'the call site substitutes the seconds into {s}');
      });

      test('$code string reads as a wait, not a rejection', () {
        lang.value = code;
        expect(tr('loginThrottled'), isNot(equals(tr('loginFailed'))));
      });
    }

    test('substitution leaves no placeholder behind', () {
      lang.value = 'en';
      final rendered = tr('loginThrottled').replaceAll('{s}', '42');
      expect(rendered.contains('{s}'), isFalse);
      expect(rendered.contains('42'), isTrue);
    });
  });
}
