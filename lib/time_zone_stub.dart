import 'package:flutter/services.dart';

// Android: MainActivity answers with java.util.TimeZone.getDefault().id.
const MethodChannel _channel = MethodChannel('nas/timezone');

Future<String?> deviceTimeZone() async {
  try {
    return await _channel.invokeMethod<String>('get');
  } catch (_) {
    return null; // tests, or a platform without the channel
  }
}
