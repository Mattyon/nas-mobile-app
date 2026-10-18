import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';
import 'package:nas_app/client_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's own log goes to the gateway (POST /client-log) and is kept with the server's
/// logs for 90 days (owner, 2026-10-18: "do all the logging, even the app").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ClientLog.I.resetForTest();
  });

  group('masking', () {
    test('credentials never reach the log', () {
      expect(ClientLog.redact('GET /tmdb/3/search?api_key=abc123&q=x'), 'GET /tmdb/3/search?api_key=***&q=x');
      expect(ClientLog.redact('Authorization: Bearer eyJhbGc.x.y'), 'Authorization: Bearer ***');
      expect(ClientLog.redact('{"password": "hunter2"}'), '{"password": "***"}');
      expect(ClientLog.redact('GET /downloads -> 200 in 12 ms'), 'GET /downloads -> 200 in 12 ms');
    });

    test('an entry is masked when it is made, data included', () {
      final Map<String, Object?> e = ClientLog.entry('info', 'api', 'token=abc', <String, Object?>{'password': 'x1'});
      expect(e['message'], 'token=***');
      expect(e['data'], isNot(contains('x1')));
    });
  });

  group('buffer', () {
    test('keeps at most maxBuffered entries and counts what it dropped', () {
      for (int i = 0; i < ClientLog.maxBuffered + 7; i++) {
        ClientLog.I.info('t', '$i');
      }
      expect(ClientLog.I.pending.length, ClientLog.maxBuffered);
      expect(ClientLog.I.pending.first['message'], '7');
      expect(ClientLog.I.droppedForTest, 7);
    });
  });

  group('flush', () {
    test('sends a batch with device, platform, version and the dropped count', () async {
      final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
      ClientLog.I.sender = (Map<String, Object?> p) async { sent.add(p); return null; };
      ClientLog.I.info('api', 'GET /downloads -> 200 in 5 ms');
      await ClientLog.I.flush();
      expect(sent, hasLength(1));
      expect(sent.single['app_version'], kAppVersion);
      expect(sent.single['platform'], isNotEmpty);
      expect((sent.single['entries']! as List<Object?>), hasLength(1));
      expect(ClientLog.I.pending, isEmpty);
    });

    test('a failed send keeps the batch for the next try', () async {
      ClientLog.I.sender = (Map<String, Object?> p) async => throw DioException(requestOptions: RequestOptions());
      ClientLog.I.info('api', 'one');
      ClientLog.I.info('api', 'two');
      await ClientLog.I.flush();
      expect(ClientLog.I.pending.map((Map<String, Object?> e) => e['message']), <String>['one', 'two']);
    });

    test('entries from background isolates are picked up and sent', () async {
      await ClientLog.persist('warning', 'bg_http', 'GET /notifications -> 401');
      final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
      ClientLog.I.sender = (Map<String, Object?> p) async { sent.add(p); return null; };
      await ClientLog.I.flush();
      final List<Object?> entries = sent.single['entries']! as List<Object?>;
      expect((entries.single! as Map<String, Object?>)['event'], 'bg_http');
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(ClientLog.pendingKey), isNull);
    });

    test('nothing is sent before there is a sender (not logged in yet)', () async {
      ClientLog.I.info('api', 'waiting');
      await ClientLog.I.flush();
      expect(ClientLog.I.pending, hasLength(1));
    });
  });

  group('the LOG_LEVEL switch', () {
    test('the gateway saying verbose is off keeps only warnings and errors', () async {
      ClientLog.I.sender = (Map<String, Object?> p) async => <String, Object?>{'ok': true, 'verbose': false};
      ClientLog.I.info('api', 'first');
      await ClientLog.I.flush();
      expect(ClientLog.I.verbose, isFalse);
      ClientLog.I.info('api', 'GET /downloads -> 200');
      ClientLog.I.warn('api', 'GET /grab -> 502');
      expect(ClientLog.I.pending.map((Map<String, Object?> e) => e['level']), <String>['warning']);
    });

    test('and back on when it says so', () async {
      ClientLog.I.verbose = false;
      ClientLog.I.sender = (Map<String, Object?> p) async => <String, Object?>{'verbose': true};
      ClientLog.I.warn('x', 'y');
      await ClientLog.I.flush();
      ClientLog.I.info('api', 'GET /downloads -> 200');
      expect(ClientLog.I.pending, hasLength(1));
    });
  });

  group('API calls', () {
    RequestOptions opts(String path) => RequestOptions(baseUrl: 'https://nas.example', path: path, method: 'GET')
      ..extra['client_log_started'] = DateTime.now().millisecondsSinceEpoch - 42;

    test('a call is logged with its status and duration', () {
      Api.logCall(opts('/downloads'), 200, null);
      final Map<String, Object?> e = ClientLog.I.pending.single;
      expect(e['level'], 'info');
      expect(e['message'] as String, matches(RegExp(r'^GET /downloads -> 200 in \d+ ms$')));
    });

    test('a failure is a warning', () {
      Api.logCall(opts('/grab'), 502, DioException(requestOptions: RequestOptions(), message: 'bad gateway'));
      expect(ClientLog.I.pending.single['level'], 'warning');
    });

    test('the log upload itself is not logged', () {
      Api.logCall(opts('/client-log'), 200, null);
      expect(ClientLog.I.pending, isEmpty);
    });
  });
}
