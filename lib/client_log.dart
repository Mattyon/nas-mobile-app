import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's version, passed at build time (`--dart-define=APP_VERSION=1.1.4`, see
/// scripts/build_web.sh); "dev" in tests and local runs.
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// The app's own log, sent to the gateway (POST /client-log), which writes it into its log
/// next to the server side -- kept 90 days (owner, 2026-10-18: "do all the logging, even
/// the app"). Every API call, every error Flutter catches, lifecycle changes and the
/// background tasks end up there, tagged with user, device, platform and app version.
///
/// Entries wait in memory (at most [maxBuffered]; the oldest go first, and how many were
/// dropped is reported) and are sent every minute, when the app goes to the background,
/// and right after an error. Background isolates (WorkManager, the push service) cannot
/// share this buffer: they use [ClientLog.persist], a small queue in SharedPreferences
/// that the app picks up on its next flush. Credentials are masked before anything is kept.
class ClientLog with WidgetsBindingObserver {
  ClientLog._();
  static final ClientLog I = ClientLog._();

  static const int maxBuffered = 500;
  static const int batchSize = 200;
  static const String pendingKey = 'client_log_pending';
  static const String deviceKey = 'client_log_device';

  final List<Map<String, Object?>> _buffer = <Map<String, Object?>>[];
  int _dropped = 0;
  bool _flushing = false;
  Timer? _timer;
  String device = '';

  /// Verbose logging on? The gateway says so in each reply (LOG_LEVEL in the NAS's .env,
  /// host/set-log-level.sh). Off: only warnings and errors are kept. On until told otherwise.
  bool verbose = true;

  /// How a batch reaches the gateway, returning its reply; set by [start]
  /// (Api.I.sendClientLog), replaced in tests.
  Future<Object?> Function(Map<String, Object?> payload)? sender;

  List<Map<String, Object?>> get pending => List<Map<String, Object?>>.unmodifiable(_buffer);

  static String platformName() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  static final RegExp _secret = RegExp(
      r'''((?:api[_-]?key|apikey|access[_-]?token|token|password|passwd|secret|authorization|x-api-key)["']?\s*[=:]\s*["']?(?:bearer\s+)?)([^&\s"',;}]+)''',
      caseSensitive: false);

  /// Mask the value of anything that looks like a credential.
  static String redact(String text) => text.replaceAllMapped(_secret, (Match m) => '${m[1]}***');

  static Map<String, Object?> entry(String level, String event, String message,
      [Map<String, Object?>? data]) {
    return <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'message': redact(message.length > 2000 ? message.substring(0, 2000) : message),
      if (data != null && data.isNotEmpty) 'data': redact(jsonEncode(data)),
    };
  }

  void add(String level, String event, String message, [Map<String, Object?>? data]) {
    if (!verbose && level != 'warning' && level != 'error') return;
    _buffer.add(entry(level, event, message, data));
    while (_buffer.length > maxBuffered) {
      _buffer.removeAt(0);
      _dropped++;
    }
    if (kDebugMode) debugPrint('[client-log] $level $event $message');
    if (level == 'error') unawaited(flush());
  }

  void info(String event, String message, [Map<String, Object?>? data]) => add('info', event, message, data);
  void warn(String event, String message, [Map<String, Object?>? data]) => add('warning', event, message, data);
  void error(String event, String message, [Map<String, Object?>? data]) => add('error', event, message, data);

  /// From a background isolate: queue the entry in SharedPreferences for the app to send.
  static Future<void> persist(String level, String event, String message,
      [Map<String, Object?>? data]) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> queue = prefs.getStringList(pendingKey) ?? <String>[];
      queue.add(jsonEncode(entry(level, event, message, <String, Object?>{...?data, 'isolate': 'background'})));
      while (queue.length > batchSize) {
        queue.removeAt(0);
      }
      await prefs.setStringList(pendingKey, queue);
    } catch (_) {
      // logging must never break the background task
    }
  }

  /// Wire it up: device id, error hooks are set by the caller; periodic flush; lifecycle.
  Future<void> start({required Future<Object?> Function(Map<String, Object?> payload) send}) async {
    sender = send;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    device = prefs.getString(deviceKey) ?? '';
    if (device.isEmpty) {
      final Random r = Random();
      device = List<String>.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString(deviceKey, device);
    }
    WidgetsBinding.instance.addObserver(this);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => flush());
    info('app_start', 'app started', <String, Object?>{'version': kAppVersion, 'platform': platformName()});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    info('lifecycle', state.name);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  /// Send what is waiting. A failed send puts the batch back (within [maxBuffered]).
  Future<void> flush() async {
    final Future<Object?> Function(Map<String, Object?>)? send = sender;
    if (send == null || _flushing) return;
    _flushing = true;
    try {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final List<String> queued = prefs.getStringList(pendingKey) ?? <String>[];
        if (queued.isNotEmpty) {
          await prefs.remove(pendingKey);
          _buffer.insertAll(0, queued.map((String s) => (jsonDecode(s) as Map).cast<String, Object?>()));
        }
      } catch (_) {}
      if (_buffer.isEmpty) return;
      final List<Map<String, Object?>> batch = _buffer.take(batchSize).toList();
      _buffer.removeRange(0, batch.length);
      final int dropped = _dropped;
      _dropped = 0;
      try {
        final Object? reply = await send(<String, Object?>{
          'device': device,
          'platform': platformName(),
          'app_version': kAppVersion,
          'dropped': dropped,
          'entries': batch,
        });
        if (reply is Map && reply['verbose'] is bool) verbose = reply['verbose'] as bool;
      } catch (_) {
        _buffer.insertAll(0, batch);
        _dropped += dropped;
        while (_buffer.length > maxBuffered) {
          _buffer.removeAt(0);
          _dropped++;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _buffer.clear();
    _dropped = 0;
    _flushing = false;
    _timer?.cancel();
    sender = null;
    verbose = true;
  }

  @visibleForTesting
  int get droppedForTest => _dropped;
}
