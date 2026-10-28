import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// The browser: Intl.DateTimeFormat().resolvedOptions().timeZone.
Future<String?> deviceTimeZone() async {
  try {
    final JSObject intl = globalContext['Intl']! as JSObject;
    final JSObject format = intl.callMethod<JSObject>('DateTimeFormat'.toJS);
    final JSObject options = format.callMethod<JSObject>('resolvedOptions'.toJS);
    return (options['timeZone'] as JSString?)?.toDart;
  } catch (_) {
    return null;
  }
}
