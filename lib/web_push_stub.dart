import 'web_push.dart';

// Not a browser (Android, tests): Web Push does not apply; the app uses ntfy.
WebPush create() => _Unsupported();

class _Unsupported implements WebPush {
  @override
  Future<PushState> state() async => PushState.unsupported;
  @override
  Future<PushState> enable(String token, String lang) async => PushState.unsupported;
  @override
  Future<PushState> disable(String token) async => PushState.unsupported;
}
