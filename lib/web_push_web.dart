import 'dart:js_interop';

import 'web_push.dart';

// The browser side lives in web/push.js (window.nasPush); this only calls it.
@JS('nasPush')
external _NasPush? get _nasPush;

extension type _NasPush._(JSObject _) implements JSObject {
  external JSPromise<JSString> state();
  external JSPromise<JSString> enable(JSString token, JSString lang);
  external JSPromise<JSString> disable(JSString token);
}

WebPush create() => _BrowserPush();

class _BrowserPush implements WebPush {
  @override
  Future<PushState> state() async {
    final _NasPush? p = _nasPush;
    if (p == null) return PushState.unsupported;
    return pushStateFrom((await p.state().toDart).toDart);
  }

  @override
  Future<PushState> enable(String token, String lang) async {
    final _NasPush? p = _nasPush;
    if (p == null) return PushState.unsupported;
    return pushStateFrom((await p.enable(token.toJS, lang.toJS).toDart).toDart);
  }

  @override
  Future<PushState> disable(String token) async {
    final _NasPush? p = _nasPush;
    if (p == null) return PushState.unsupported;
    return pushStateFrom((await p.disable(token.toJS).toDart).toDart);
  }
}
