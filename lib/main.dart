import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'api.dart';
import 'detail.dart';
import 'i18n.dart';
import 'user_permissions.dart';

final ValueNotifier<int> authTick = ValueNotifier<int>(0);
final ValueNotifier<int> selectedTab = ValueNotifier<int>(0); // 0=Search 1=Downloads 2=Library
final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

// ----------------------------- local notifications --------------------------
final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _dlChannel = AndroidNotificationChannel(
  'downloads',
  'Downloads',
  description: 'Download completion alerts',
  importance: Importance.high,
);

const AndroidNotificationChannel _alertChannel = AndroidNotificationChannel(
  'nas_alerts',
  'NAS Alerts',
  description: 'NAS download completions, errors, and health alerts',
  importance: Importance.high,
);

Future<void> _initNotifications() async {
  const AndroidInitializationSettings android =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await _flnp.initialize(settings: const InitializationSettings(android: android));
  final AndroidFlutterLocalNotificationsPlugin? ap = _flnp
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await ap?.createNotificationChannel(_dlChannel);
  await ap?.createNotificationChannel(_alertChannel);
  await ap?.requestNotificationsPermission();
}

Future<void> _notifyDownloadDone(String name) async {
  await _flnp.show(
    id: name.hashCode.abs() % 100000,
    title: 'Download complete',
    body: name,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _dlChannel.id,
        _dlChannel.name,
        channelDescription: _dlChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

Future<void> _showSystemNotification(Map<String, dynamic> n) async {
  final bool cs = lang.value == 'cs';
  final String title = (cs
          ? (n['title_cs']?.toString() ?? n['title']?.toString())
          : n['title']?.toString()) ??
      '';
  final String body = (cs
          ? (n['body_cs']?.toString() ?? n['body']?.toString())
          : n['body']?.toString()) ??
      '';
  await _flnp.show(
    id: (n['id'] as int? ?? 0).abs() % 100000,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannel.id,
        _alertChannel.name,
        channelDescription: _alertChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

/// Compact relative timestamp: "now", "5m", "2h", "3d", "8.6."
String _formatTs(String? ts) {
  if (ts == null || ts.isEmpty) return '';
  try {
    final DateTime dt = DateTime.parse(ts).toLocal();
    final Duration diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}.${dt.month}.';
  } catch (_) {
    return '';
  }
}

// ----------------------------- background task (WorkManager) -----------------

/// WorkManager callback dispatcher — runs in a separate Dart isolate.
/// Must be a top-level function annotated @pragma('vm:entry-point').
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    await _bgPollNotifications();
    return true;
  });
}

/// Raw HTTP GET in the background isolate (Dio is not available here).
Future<Map<String, dynamic>?> _bgHttpGet(String url, String token) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final HttpClientRequest req = await client.getUrl(Uri.parse(url));
    req.headers.set('Authorization', 'Bearer $token');
    final HttpClientResponse resp = await req.close();
    if (resp.statusCode != 200) return null;
    final String body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client?.close();
  }
}

/// POST to /login; returns the new JWT on success.
Future<String?> _bgReauth(String baseUrl, FlutterSecureStorage secure) async {
  try {
    final String? expStr = await secure.read(key: 'rememberExpiry');
    final int exp = int.tryParse(expStr ?? '') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch >= exp) return null;
    final String? user = await secure.read(key: 'rememberUser');
    final String? pass = await secure.read(key: 'rememberPass');
    if (user == null || pass == null) return null;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final HttpClientRequest req = await client.postUrl(Uri.parse('$baseUrl/login'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(<String, String>{'username': user, 'password': pass}));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != 200) return null;
      final String body = await resp.transform(utf8.decoder).join();
      final String? newToken =
          (jsonDecode(body) as Map<String, dynamic>)['token'] as String?;
      if (newToken != null) await secure.write(key: 'token', value: newToken);
      return newToken;
    } finally {
      client?.close();
    }
  } catch (_) {
    return null;
  }
}

/// Core background notification poll — same logic as the foreground bell but
/// runs in a WorkManager isolate and therefore works even when the app is killed.
Future<void> _bgPollNotifications() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String baseUrl =
      prefs.getString('baseUrl') ?? 'https://nas.mattyzem.com';
  final int lastId = prefs.getInt('last_notif_id') ?? 0;
  final String appLang = prefs.getString('app_lang') ?? 'en';

  const FlutterSecureStorage secure = FlutterSecureStorage();
  String? token = await secure.read(key: 'token');

  // Fetch; on 401 try to get a fresh token and retry once.
  Map<String, dynamic>? data = await _bgHttpGet('$baseUrl/notifications', token ?? '');
  if (data == null) {
    token = await _bgReauth(baseUrl, secure);
    if (token == null) return;
    data = await _bgHttpGet('$baseUrl/notifications', token);
    if (data == null) return;
  }

  final List<dynamic> items =
      (data['notifications'] as List<dynamic>?) ?? <dynamic>[];
  final List<Map<String, dynamic>> fresh = items
      .whereType<Map<String, dynamic>>()
      .where((Map<String, dynamic> n) => (n['id'] as int? ?? 0) > lastId)
      .toList();
  if (fresh.isEmpty) return;

  final int newMax = fresh
      .map((Map<String, dynamic> n) => n['id'] as int? ?? 0)
      .reduce((int a, int b) => a > b ? a : b);
  await prefs.setInt('last_notif_id', newMax);

  final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings android =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await flnp.initialize(settings: const InitializationSettings(android: android));

  final bool cs = appLang == 'cs';
  for (final Map<String, dynamic> n in fresh.take(3)) {
    final String title = (cs
            ? (n['title_cs']?.toString() ?? n['title']?.toString())
            : n['title']?.toString()) ??
        '';
    final String body = (cs
            ? (n['body_cs']?.toString() ?? n['body']?.toString())
            : n['body']?.toString()) ??
        '';
    await flnp.show(
      id: (n['id'] as int? ?? 0).abs() % 100000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'nas_alerts',
          'NAS Alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}

// ----------------------------- instant push (foreground service) -------------
//
// The 15-min WorkManager poll above is a safety net; this is the primary path.
// A foreground service holds one persistent connection to /notifications/stream
// (the gateway's proxy onto self-hosted ntfy) and re-fetches /notifications the
// instant something arrives, instead of waiting for the next periodic poll.

/// Runs in its own isolate — set up via [_pushStreamCallback].
class _PushStreamTaskHandler extends TaskHandler {
  bool _stopped = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _stopped = false;
    unawaited(_runLoop());
  }

  Future<void> _runLoop() async {
    while (!_stopped) {
      Duration backoff = const Duration(seconds: 10);
      try {
        backoff = await _streamOnce();
      } catch (_) {
        // network hiccup / parse error — fall through to the default backoff
      }
      if (_stopped) break;
      await Future<void>.delayed(backoff);
    }
  }

  /// Opens one streaming connection and processes it until it ends or errors.
  /// Returns how long to wait before the next reconnect attempt.
  Future<Duration> _streamOnce() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String baseUrl =
        prefs.getString('baseUrl') ?? 'https://nas.mattyzem.com';
    const FlutterSecureStorage secure = FlutterSecureStorage();
    final String? token = await secure.read(key: 'token');
    if (token == null) return const Duration(seconds: 30);

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final HttpClientRequest req =
          await client.getUrl(Uri.parse('$baseUrl/notifications/stream'));
      req.headers.set('Authorization', 'Bearer $token');
      final HttpClientResponse resp = await req.close();

      if (resp.statusCode == 401) {
        await _bgReauth(baseUrl, secure);
        return const Duration(seconds: 2); // retry immediately with the fresh token
      }
      if (resp.statusCode != 200) return const Duration(seconds: 15);

      await for (final String line
          in resp.transform(utf8.decoder).transform(const LineSplitter())) {
        if (_stopped) break;
        if (line.trim().isEmpty) continue;
        Map<String, dynamic>? evt;
        try {
          evt = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue; // ntfy sends non-JSON keepalive bytes on some proxies — ignore
        }
        if (evt['event'] == 'message') await _bgPollNotifications();
      }
      return const Duration(seconds: 5); // stream ended cleanly — reconnect promptly
    } finally {
      client?.close(force: true);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopped = true;
  }
}

/// Top-level entry point required by flutter_foreground_task — runs in the
/// service isolate, not the UI isolate.
@pragma('vm:entry-point')
void _pushStreamCallback() {
  FlutterForegroundTask.setTaskHandler(_PushStreamTaskHandler());
}

void _initPushService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      // NOTE: Android locks a channel's importance at creation time — changing it
      // later is ignored. The channelId is versioned (…_v2) so this MIN-importance
      // channel is created fresh, actually silencing the persistent notification
      // (no sound, no heads-up, no status-bar icon; shows only low in the shade).
      channelId: 'nas_push_listener_v2',
      channelName: 'Background connection',
      channelDescription:
          'Keeps the app connected so NAS alerts arrive immediately.',
      channelImportance: NotificationChannelImportance.MIN,
      priority: NotificationPriority.MIN,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<void> _startPushService() async {
  if (await FlutterForegroundTask.checkNotificationPermission() !=
      NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
    return;
  }
  await FlutterForegroundTask.startService(
    serviceId: 257,
    serviceTypes: const [ForegroundServiceTypes.dataSync],
    // Minimal, non-annoying text (the service notification can't be removed on
    // Android, only made unobtrusive via the MIN channel above).
    notificationTitle: 'NAS',
    notificationText: '',
    callback: _pushStreamCallback,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Api.I.init();
  if (Platform.isAndroid) await _initNotifications();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool isDark = prefs.getBool('darkMode') ?? true;
  themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  lang.value = prefs.getString('app_lang') ?? 'en';
  if (Platform.isAndroid) {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      'nas_notif_periodic',
      'poll_notifications',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    FlutterForegroundTask.initCommunicationPort();
    _initPushService();
    await _startPushService();
  }
  runApp(const NasApp());
}

Future<void> _toggleTheme() async {
  final isDark = themeMode.value == ThemeMode.dark;
  themeMode.value = isDark ? ThemeMode.light : ThemeMode.dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('darkMode', !isDark);
}

Future<void> _toggleLang() async {
  toggleLang();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_lang', lang.value);
}

class NasApp extends StatelessWidget {
  const NasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (BuildContext context, ThemeMode mode, Widget? _) => MaterialApp(
        title: 'NAS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.light,
            useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark,
            useMaterial3: true),
        themeMode: mode,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    Api.I.onUnauthorized = () {
      if (mounted) authTick.value++;
    };
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    if (!Api.I.isLoggedIn) {
      final hasIt = await Api.I.hasRememberedCredentials();
      if (hasIt) {
        final ok = await Api.I.biometricAutoLogin();
        if (ok && mounted) authTick.value++;
      }
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ValueListenableBuilder<int>(
      valueListenable: authTick,
      builder: (BuildContext context, int _, Widget? __) {
        return Api.I.isLoggedIn ? const HomeShell() : const LoginScreen();
      },
    );
  }
}

class LangButton extends StatelessWidget {
  const LangButton({super.key});
  @override
  Widget build(BuildContext context) {
    // Self-updating even though instances are const: rebuilds on language change
    // so the label always offers the *other* language.
    return ValueListenableBuilder<String>(
      valueListenable: lang,
      builder: (BuildContext context, String code, Widget? _) => IconButton(
        onPressed: _toggleLang,
        tooltip: tr('language'),
        icon: Text(code == 'cs' ? '🇨🇿' : '🇬🇧', style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

// ----------------------------- notification bell ----------------------------
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with LangAware {
  List<dynamic> _items = <dynamic>[];
  int _unreadCount = 0;
  int _lastSeenId = 0;  // persisted across launches; baseline for system-notification dedup
  bool _baselineSet = false; // true after first poll — prevents stale items re-notifying
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAndPoll();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAndPoll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _lastSeenId = prefs.getInt('last_notif_id') ?? 0;
    await _poll();
  }

  Future<void> _poll() async {
    try {
      final Map<String, dynamic> data = await Api.I.notifications();
      final List<dynamic> items = (data['notifications'] as List<dynamic>?) ?? <dynamic>[];
      final int unread = (data['unread_count'] as int?) ?? 0;

      // Detect notifications newer than the last one we processed.
      final List<Map<String, dynamic>> fresh = items
          .whereType<Map<String, dynamic>>()
          .where((Map<String, dynamic> n) => (n['id'] as int? ?? 0) > _lastSeenId)
          .toList();

      if (fresh.isNotEmpty) {
        final int newMax = fresh
            .map((Map<String, dynamic> n) => n['id'] as int? ?? 0)
            .reduce((int a, int b) => a > b ? a : b);
        _lastSeenId = newMax;
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_notif_id', newMax);

        // Only fire system notifications after the baseline poll — prevents
        // re-notifying for items that were already in the list when the app launched.
        if (_baselineSet) {
          for (final Map<String, dynamic> n in fresh.take(3)) {
            await _showSystemNotification(n);
          }
        }
      }
      _baselineSet = true;

      if (mounted) setState(() { _items = items; _unreadCount = unread; });
    } catch (_) {}
  }

  Future<void> _clear() async {
    try {
      await Api.I.clearNotifications();
      if (mounted) setState(() => _items = <dynamic>[]);
    } catch (_) {}
  }

  void _show() {
    // Clear unread badge immediately; fire-and-forget to server.
    setState(() => _unreadCount = 0);
    Api.I.markNotificationsRead().catchError((_) {});
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (BuildContext ctx2, ScrollController sc) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(tr('notifications'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  if (_items.isNotEmpty)
                    TextButton(onPressed: () { _clear(); Navigator.pop(ctx2); },
                        child: Text(tr('clearAll'))),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _items.isEmpty
                  ? Center(child: Text(tr('noNotifications'),
                      style: const TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      controller: sc,
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext c, int i) {
                        final Map<String, dynamic> n =
                            _items[i] as Map<String, dynamic>;
                        final bool cs = lang.value == 'cs';
                        final String displayTitle = cs
                            ? (n['title_cs']?.toString() ?? n['title']?.toString() ?? '')
                            : (n['title']?.toString() ?? '');
                        final String displayBody = cs
                            ? (n['body_cs']?.toString() ?? n['body']?.toString() ?? '')
                            : (n['body']?.toString() ?? '');
                        final String timeStr = _formatTs(n['ts']?.toString());
                        return ListTile(
                          title: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              Expanded(
                                child: Text(displayTitle,
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                              ),
                              if (timeStr.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(timeStr,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500])),
                                ),
                            ],
                          ),
                          subtitle: Text(displayBody,
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                          dense: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ).then((_) => _poll());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _show,
          tooltip: tr('notifications'),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 8, top: 8,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _unreadCount > 9 ? '9+' : '$_unreadCount',
                style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// Official cover art (loaded from the TMDb/TVDB URL the gateway provides).
/// The list-sized poster for a search/library row.
///
/// The gateway serves `poster` as the full-size original — a TVDB poster is ~440 KB,
/// a TMDb one up to 1.2 MB — and `poster_thumb` as the ~40 KB version meant for a
/// 46x69 row. Falls back to the full URL so a gateway that predates `poster_thumb`
/// still shows artwork rather than blank rows.
/// How many episodes a library row is missing, or null when that is not knowable.
///
/// Null and zero are deliberately the same answer to the caller: a movie carries no
/// episode counts at all, and a complete series carries a zero. Neither should draw a
/// badge, and "0 missing" on a finished show is noise.
int? missingEpisodeCount(Map<String, dynamic> item) {
  final Object? missing = item['missing_count'];
  return missing is int && missing > 0 ? missing : null;
}


/// Amber "missing episodes" marker for a library row.
///
/// The count leads, and it is a number rather than a translated word, so the badge is
/// the same width in Czech as in English — the language-filter chips had to be
/// rewritten for exactly that reason. The full sentence lives in a tooltip.
class IncompleteBadge extends StatelessWidget {
  const IncompleteBadge({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final int? missing = missingEpisodeCount(item);
    if (missing == null) return const SizedBox.shrink();
    final Object? have = item['episode_file_count'];
    final Object? total = item['episode_count'];
    final String tip = (have is int && total is int)
        ? tr('episodesDownloaded')
            .replaceAll('{have}', '$have')
            .replaceAll('{total}', '$total')
        : tr('episodesMissing').replaceAll('{n}', '$missing');
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
          const SizedBox(width: 3),
          Text('$missing',
              style: const TextStyle(fontSize: 11, color: Colors.amber,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}


/// Opens a URL in the browser, or whichever app claims it.
///
/// Returns false when nothing on the device can handle it, so the caller can say
/// so. _LinkRow launches inline and swallows that case, which is fine for a link
/// inside a help sheet but not for a menu item: a tap that silently does nothing
/// is indistinguishable from a broken build.
Future<bool> openExternalUrl(String url) async {
  final Uri uri = Uri.parse(url);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}


String? rowPosterUrl(Map<String, dynamic> item) {
  final Object? thumb = item['poster_thumb'];
  if (thumb is String && thumb.isNotEmpty) return thumb;
  final Object? full = item['poster'];
  return full is String && full.isNotEmpty ? full : null;
}


class PosterImage extends StatelessWidget {
  final String? url;
  const PosterImage(this.url, {super.key});
  static const double _w = 46, _h = 69;

  /// Cap for the *decoded* copy, in raw pixels.
  ///
  /// The gateway hands out full-size artwork — a TVDB poster is typically 680x1000
  /// and 100-200 KB — and this renders it at 46x69. Without a cap, every row decodes
  /// a full-resolution bitmap and keeps it in memory to draw a thumbnail. 210 px wide
  /// covers 46 logical pixels at any sane device ratio, including 4x.
  ///
  /// Deliberately NOT paired with `maxWidthDiskCache`: that does not replace the
  /// stored original, it writes a second, resized file beside it. Measured on the
  /// emulator, seven posters became fourteen files — seven originals at up to 1.2 MB
  /// plus seven thumbnails — so it costs disk rather than saving it. The real fix for
  /// download size is the gateway handing out a thumbnail URL in the first place.
  static const int _decodeWidth = 210;

  Widget _fallback(IconData icon) =>
      Container(width: _w, height: _h, color: Colors.black26, child: Icon(icon, size: 20));

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _fallback(Icons.movie_outlined);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        memCacheWidth: _decodeWidth,
        // Same shapes as before, so a slow or missing image still occupies its row
        // rather than collapsing the list.
        errorWidget: (_, _, _) => _fallback(Icons.broken_image_outlined),
        placeholder: (_, _) => _fallback(Icons.image_outlined),
        // Once it is on disk the second display should be instant, not a fade.
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: Duration.zero,
      ),
    );
  }
}

// ----------------------------- login ----------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with LangAware {
  final TextEditingController _url =
      TextEditingController(text: Api.I.baseUrl);
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _rememberMe = false;
  bool _canBio = false;
  bool _hasRemembered = false;
  String? _rememberedUser;

  @override
  void initState() {
    super.initState();
    _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    final canBio = await Api.I.canUseBiometrics();
    final hasRem = await Api.I.hasRememberedCredentials();
    final remUser = await Api.I.rememberedUsername();
    if (mounted) {
      setState(() {
        _canBio = canBio;
        _hasRemembered = hasRem;
        _rememberedUser = remUser;
        if (_hasRemembered) _rememberMe = true;
      });
    }
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await Api.I.setBaseUrl(_url.text);
      await Api.I.login(_user.text.trim(), _pass.text);
      if (_rememberMe) {
        await Api.I.saveRememberedCredentials(_user.text.trim(), _pass.text);
      } else {
        await Api.I.clearRememberedCredentials();
      }
      authTick.value++;
    } on LoginThrottled catch (e) {
      // Not a wrong password — retrying now cannot succeed, so say how long to wait
      // rather than sending the user round the same loop.
      setState(() => _error =
          tr('loginThrottled').replaceAll('{s}', '${e.retryAfterSeconds}'));
    } catch (_) {
      setState(() => _error = tr('loginFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometricLogin() async {
    setState(() { _busy = true; _error = null; });
    final ok = await Api.I.biometricAutoLogin();
    if (!mounted) return;
    if (ok) {
      authTick.value++;
    } else {
      setState(() { _busy = false; _error = tr('loginFailed'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('app')), actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: tr('helpConnect'),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
        ),
        const LangButton(),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              if (_canBio && _hasRemembered) ...<Widget>[
                FilledButton.icon(
                  onPressed: _busy ? null : _biometricLogin,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_rememberedUser != null
                      ? '${tr('loginWithBiometrics')} ($_rememberedUser)'
                      : tr('loginWithBiometrics')),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _url,
                readOnly: true,
                decoration: InputDecoration(labelText: tr('serverUrl')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _user,
                decoration: InputDecoration(labelText: tr('username')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('password')),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('rememberMe')),
                value: _rememberMe,
                onChanged: _busy ? null : (bool? v) => setState(() => _rememberMe = v ?? false),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(tr('login')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------- shell ----------------------------------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with LangAware {
  static const List<Widget> _pages = <Widget>[
    SearchScreen(),
    DownloadsScreen(),
    LibraryScreen(),
  ];

  Future<void> _showSpeedDialog(BuildContext context) async {
    Map<String, dynamic> current;
    try {
      current = await Api.I.qbtLimits();
    } catch (_) {
      current = <String, dynamic>{};
    }
    final TextEditingController dlCtrl = TextEditingController(
        text: ((current['dl_mbps'] as num?) ?? 0).toStringAsFixed(1));
    final TextEditingController upCtrl = TextEditingController(
        text: ((current['up_mbps'] as num?) ?? 0).toStringAsFixed(1));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('speedLimits')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
                controller: dlCtrl,
                decoration: InputDecoration(labelText: tr('dlLimit')),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 8),
            TextField(
                controller: upCtrl,
                decoration: InputDecoration(labelText: tr('upLimit')),
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                OutlinedButton.icon(
                  icon: const Icon(Icons.pause_circle_outline),
                  label: Text(tr('pauseAll')),
                  onPressed: () async {
                    try {
                      await Api.I.qbtPause();
                    } catch (_) {}
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(tr('resumeAll')),
                  onPressed: () async {
                    try {
                      await Api.I.qbtResume();
                    } catch (_) {}
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('cancel'))),
          FilledButton(
            child: Text(tr('save')),
            onPressed: () async {
              final double dl = double.tryParse(dlCtrl.text) ?? 0;
              final double up = double.tryParse(upCtrl.text) ?? 0;
              try {
                await Api.I.setQbtLimits(dl, up);
              } catch (_) {}
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showJellyfinSettingsDialog(BuildContext context) async {
    final TextEditingController urlCtrl =
        TextEditingController(text: Api.I.jellyfinUrl);
    bool saving = false;
    String? status;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setState) => AlertDialog(
          title: const Text('Jellyfin URL'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Set the Jellyfin server URL for Android Auto playback.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://jellyfin.mattyzem.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              if (status != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(status!, style: TextStyle(
                  fontSize: 12,
                  color: status!.startsWith('✓') ? Colors.green : Colors.redAccent,
                )),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: saving ? null : () async {
                setState(() { saving = true; status = null; });
                try {
                  await Api.I.setJellyfinUrl(urlCtrl.text.trim());
                  await Api.I.reseedJellyfinToken();
                  setState(() { status = '✓ Saved & token refreshed'; saving = false; });
                } catch (_) {
                  setState(() { status = 'Saved URL (token refresh failed — will retry on next login)'; saving = false; });
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: selectedTab,
      builder: (BuildContext context, int tab, Widget? _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('app')),
          actions: <Widget>[
            const NotificationBell(),
            const LangButton(),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeMode,
              builder: (BuildContext ctx2, ThemeMode mode, Widget? _) =>
                  PopupMenuButton<String>(
                icon: const Icon(Icons.menu),
                onSelected: (String v) async {
                  if (v == 'neweps') {
                    try {
                      await Api.I.triggerNewEpisodeCheck();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(tr('newEpsStarted'))));
                      }
                    } catch (_) {}
                  } else if (v == 'health') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const HealthCheckScreen()));
                  } else if (v == 'kuma') {
                    if (!await openExternalUrl(Api.I.kumaUrl) && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('kumaOpenFailed'))));
                    }
                  } else if (v == 'speedtest') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const SpeedtestScreen()));
                  } else if (v == 'ai') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const AiChatsListScreen()));
                  } else if (v == 'tapo') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const TapoDevicesScreen()));
                  } else if (v == 'camera') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const CameraListScreen()));
                  } else if (v == 'help') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const HelpScreen()));
                  } else if (v == 'sessions') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const SessionsScreen()));
                  } else if (v == 'users') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const UsersScreen()));
                  } else if (v == 'speed') {
                    _showSpeedDialog(context);
                  } else if (v == 'jellyfin') {
                    _showJellyfinSettingsDialog(context);
                  } else if (v == 'theme') {
                    await _toggleTheme();
                  } else if (v == 'logout') {
                    await Api.I.logout();
                    authTick.value++;
                  } else if (v == 'kill') {
                    exit(0);
                  }
                },
                itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(Api.I.displayName ?? Api.I.username ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(Api.I.role,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'sessions',
                      child: Row(children: <Widget>[
                        const Icon(Icons.cast_connected, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('mediaSessions')),
                      ]),
                    ),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'speed',
                      child: Row(children: <Widget>[
                        const Icon(Icons.speed, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('speedLimits')),
                      ]),
                    ),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'users',
                      child: Row(children: <Widget>[
                        const Icon(Icons.people, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('userManagement')),
                      ]),
                    ),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'tapo',
                      child: Row(children: <Widget>[
                        const Icon(Icons.power_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('tapoDevices')),
                      ]),
                    ),
                  if (Api.I.isSuperadmin)
                    PopupMenuItem<String>(
                      value: 'ai',
                      child: Row(children: <Widget>[
                        const Icon(Icons.smart_toy_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('aiChats')),
                      ]),
                    ),
                  if (Api.I.isSuperadmin)
                    PopupMenuItem<String>(
                      value: 'camera',
                      child: Row(children: <Widget>[
                        const Icon(Icons.videocam_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('cameraFeed')),
                      ]),
                    ),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'speedtest',
                      child: Row(children: <Widget>[
                        const Icon(Icons.network_check, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('speedtest')),
                      ]),
                    ),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'health',
                      child: Row(children: <Widget>[
                        const Icon(Icons.health_and_safety_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('healthCheck')),
                      ]),
                    ),
                  if (Api.I.isAdmin)
                    PopupMenuItem<String>(
                      value: 'kuma',
                      child: Row(children: <Widget>[
                        const Icon(Icons.monitor_heart_outlined, size: 20),
                        const SizedBox(width: 12),
                        // Untranslated on purpose: it is a product name, and the
                        // menu already carries 'Jellyfin URL' the same way.
                        const Text('Uptime Kuma'),
                      ]),
                    ),
                  PopupMenuItem<String>(
                    value: 'neweps',
                    child: Row(children: <Widget>[
                      const Icon(Icons.tv, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('checkNewEps')),
                    ]),
                  ),
                  PopupMenuItem<String>(
                    value: 'jellyfin',
                    child: Row(children: <Widget>[
                      const Icon(Icons.play_circle_outline, size: 20),
                      const SizedBox(width: 12),
                      const Text('Jellyfin URL'),
                    ]),
                  ),
                  PopupMenuItem<String>(
                    value: 'theme',
                    child: Row(children: <Widget>[
                      Icon(mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                          size: 20),
                      const SizedBox(width: 12),
                      Text(mode == ThemeMode.dark ? tr('lightMode') : tr('darkMode')),
                    ]),
                  ),
                  PopupMenuItem<String>(
                    value: 'help',
                    child: Row(children: <Widget>[
                      const Icon(Icons.help_outline, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('helpConnect')),
                    ]),
                  ),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(children: <Widget>[
                      const Icon(Icons.logout, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('logout')),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'kill',
                    child: Row(children: <Widget>[
                      const Icon(Icons.power_settings_new, size: 20,
                          color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Text(tr('killApp'),
                          style: const TextStyle(color: Colors.redAccent)),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: _pages[tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (int i) => selectedTab.value = i,
          destinations: <NavigationDestination>[
            NavigationDestination(icon: const Icon(Icons.search), label: tr('search')),
            NavigationDestination(icon: const Icon(Icons.download), label: tr('downloads')),
            NavigationDestination(icon: const Icon(Icons.video_library), label: tr('library')),
          ],
        ),
      ),
    );
  }
}

Widget _errorView(String message, VoidCallback onRetry) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

// ----------------------------- search ---------------------------------------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with LangAware {
  final TextEditingController _q = TextEditingController();
  List<dynamic> _results = <dynamic>[];
  bool _busy = false;
  bool _searched = false; // a search has actually run
  String? _grabbing; // key of the item currently being requested

  @override
  void initState() {
    super.initState(); // LangAware adds its rebuild listener
    lang.addListener(_reSearchOnLang);
  }

  @override
  void dispose() {
    lang.removeListener(_reSearchOnLang);
    super.dispose();
  }

  // Re-run the search on language change so titles re-localize (cs <-> en).
  void _reSearchOnLang() {
    if (_searched && _q.text.trim().isNotEmpty) _run();
  }

  String _key(Map<String, dynamic> m) =>
      '${m['type']}-${m['tmdbId'] ?? m['tvdbId']}';

  Widget _typeBadge(String? t) {
    final bool isTv = t == 'tv';
    final Color c = isTv ? Colors.purpleAccent : Colors.tealAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4)),
      child: Text(isTv ? tr('tv') : tr('movie'),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _run() async {
    if (_q.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _searched = true;
      _results = <dynamic>[];
    });
    try {
      final List<dynamic> r = await Api.I.search(_q.text.trim(), 'any', lang: lang.value);
      setState(() => _results = r);
    } catch (_) {
      setState(() => _results = <dynamic>[]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _emptyState() {
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: _searched
          ? Text(tr('noResults'))
          : Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Opacity(
                    opacity: 0.5,
                    child: Image.asset('assets/icon/icon.png', width: 140, height: 140),
                  ),
                  const SizedBox(height: 16),
                  Text(tr('searchEmptyTitle'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(tr('searchEmptyHint'),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
    );
  }

  Future<void> _grab(Map<String, dynamic> item) async {
    // Step 0: source picker (ThePirateBay is AI-access only; others skip this step).
    String source = 'prowlarr';
    if (Api.I.isSuperadmin) {
      final String? picked = await _pickSource();
      if (picked == null || !mounted) return;
      source = picked;
    }
    // Step 1: language picker
    final String? language = await _pickLanguage(item);
    if (language == null || !mounted) return;
    // Step 2: quality picker
    final String? tier = await _pickQuality(language);
    if (tier == null || !mounted) return;
    await _doGrab(item, language, tier, source);
  }

  Future<String?> _pickSource() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('pickSource'),
                    style: Theme.of(ctx).textTheme.titleMedium)),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(tr('sourceStandard')),
            subtitle: Text(tr('sourceStandardDesc')),
            onTap: () => Navigator.pop(ctx, 'prowlarr'),
          ),
          ListTile(
            leading: const Icon(Icons.psychology),
            title: Text(tr('sourceTpb')),
            subtitle: Text(tr('sourceTpbDesc')),
            onTap: () => Navigator.pop(ctx, 'tpb'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<String?> _pickLanguage(Map<String, dynamic> item) {
    final bool hasEn = item['on_disk_en'] == true;
    final bool hasCs = item['on_disk_cs'] == true;
    final String appLang = lang.value; // app's current language = default
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) {
        Widget tile({
          required String code,
          required String flag,
          required String label,
          String? source,
          required bool onDisk,
        }) {
          final bool isDefault = code == appLang;
          final List<String> subParts = <String>[
            if (isDefault) tr('appLanguage'),
            if (source != null) source,
          ];
          return ListTile(
            selected: isDefault,
            leading: Text(flag, style: const TextStyle(fontSize: 24)),
            title: Text(label),
            subtitle: subParts.isNotEmpty
                ? Text(subParts.join(' · '), style: const TextStyle(fontSize: 11))
                : null,
            trailing: onDisk
                ? const Icon(Icons.check_circle_outline, color: Colors.green, size: 20)
                : null,
            onTap: () => Navigator.pop(ctx, code),
          );
        }

        final Widget enTile = tile(
            code: 'en', flag: '🇬🇧', label: tr('langEnglish'), onDisk: hasEn);
        final Widget csTile = tile(
            code: 'cs', flag: '🇨🇿', label: tr('langCzech'),
            source: 'sktorrent.eu', onDisk: hasCs);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('pickLanguage'),
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
              ),
              // App language comes first
              if (appLang == 'cs') ...<Widget>[csTile, enTile]
              else ...<Widget>[enTile, csTile],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _pickQuality(String language) {
    final String flag = language == 'cs' ? '🇨🇿' : '🇬🇧';
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: <Widget>[
                Text(flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(tr('pickQuality'),
                    style: Theme.of(ctx).textTheme.titleMedium),
              ]),
            ),
            for (final String t in <String>['fast', 'balanced', 'best'])
              ListTile(
                leading: Icon(
                  t == 'fast' ? Icons.flash_on_outlined :
                  t == 'best' ? Icons.star_outline : Icons.balance_outlined,
                ),
                title: Text(tr(t)),
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _doGrab(Map<String, dynamic> item, String language, String tier,
      String source) async {
    setState(() => _grabbing = _key(item));
    final VoidCallback closeStages = _showStages();
    final String itype = item['type']?.toString() ?? 'movie';
    try {
      final Map<String, dynamic> result = await Api.I.grab(
        type: itype,
        tmdbId: itype == 'movie' ? item['tmdbId'] as int? : null,
        tvdbId: itype == 'tv' ? item['tvdbId'] as int? : null,
        tier: tier,
        language: language,
        source: source,
      );

      if (result['no_czech_audio'] == true) {
        closeStages();
        if (mounted) setState(() => _grabbing = null);
        await _offerEnglishFallback(
            item, tier, result['title']?.toString() ?? '', source);
        return;
      }

      // Update local on_disk state immediately.
      if (mounted) {
        setState(() {
          if (itype == 'tv') {
            // Backend returns current registry state; use it to correct stale Flutter flags.
            if (result.containsKey('on_disk_en')) item['on_disk_en'] = result['on_disk_en'];
            if (result.containsKey('on_disk_cs')) item['on_disk_cs'] = result['on_disk_cs'];
          } else if (language == 'en') {
            item['on_disk_en'] = true;
          } else if (language == 'cs') {
            item['on_disk_cs'] = true;
          }
        });
      }
      _snackGo(itype == 'tv' ? tr('requestedTv') : tr('added'));
    } catch (_) {
      _snack(tr('error'));
    } finally {
      closeStages();
      if (mounted) setState(() => _grabbing = null);
    }
  }

  Future<void> _offerEnglishFallback(
      Map<String, dynamic> item, String tier, String title, String source) async {
    final String tierLabel = tr(tier);
    final String msg = tr('noCzechAudioMsg')
        .replaceFirst('{title}', title)
        .replaceFirst('{tier}', tierLabel);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('noCzechAudio')),
        content: Text(msg),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('downloadInEnglish'))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _doGrab(item, 'en', tier, source);
    }
  }

  /// Modal with a spinner that cycles through stage messages while we wait.
  VoidCallback _showStages() {
    final List<String> stages = <String>[
      tr('stageSearch'), tr('stageDatabases'), tr('stagePick'), tr('stageStart'),
    ];
    final ValueNotifier<int> step = ValueNotifier<int>(0);
    final Timer timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (step.value < stages.length - 1) step.value++;
    });
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 18),
              Flexible(
                child: ValueListenableBuilder<int>(
                  valueListenable: step,
                  builder: (_, int i, _) => Text(stages[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return () {
      timer.cancel();
      step.dispose();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    };
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  // Snackbar with a "Downloads" action that jumps to the Downloads tab.
  void _snackGo(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      duration: const Duration(seconds: 6),
      // Dismiss by swiping left or right (instead of the default downward swipe).
      dismissDirection: DismissDirection.horizontal,
      action: SnackBarAction(
        label: tr('downloads'),
        onPressed: () => selectedTab.value = 1,
      ),
    ));
  }

  Widget _langChips(Map<String, dynamic> item) {
    final bool hasEn = item['on_disk_en'] == true;
    final bool hasCs = item['on_disk_cs'] == true;
    if (!hasEn && !hasCs) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      if (hasEn) const Text('🇬🇧', style: TextStyle(fontSize: 13)),
      if (hasEn && hasCs) const SizedBox(width: 2),
      if (hasCs) const Text('🇨🇿', style: TextStyle(fontSize: 13)),
    ]);
  }

  Widget _buildTrailing(Map<String, dynamic> item, bool busy) {
    final bool hasEn = item['on_disk_en'] == true;
    final bool hasCs = item['on_disk_cs'] == true;
    final bool inLibrary = hasEn && hasCs;
    final Widget chips = _langChips(item);
    final Widget dlBtn = SizedBox(
      height: 30,
      child: FilledButton.tonal(
        onPressed: busy ? null : () => _grab(item),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: busy
            ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(tr('download')),
      ),
    );
    if (inLibrary) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          chips,
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.check_circle, size: 13, color: Colors.green),
            const SizedBox(width: 3),
            Text(tr('inLibraryBoth'),
                style: const TextStyle(fontSize: 10, color: Colors.green)),
          ]),
        ],
      );
    }
    if (hasEn || hasCs) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[chips, const SizedBox(height: 3), dlBtn],
      );
    }
    return dlBtn;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: tr('searchHint'),
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? _emptyState()
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Map<String, dynamic> m = _results[i] as Map<String, dynamic>;
                    final bool busy = _grabbing == _key(m);
                    return ListTile(
                      onTap: () => Navigator.push<void>(context,
                          MaterialPageRoute<void>(
                              builder: (_) => DetailScreen(item: m))),
                      leading: PosterImage(rowPosterUrl(m)),
                      title: Text(m['title']?.toString() ?? ''),
                      subtitle: Row(
                        children: <Widget>[
                          _typeBadge(m['type']?.toString()),
                          const SizedBox(width: 6),
                          Text(m['year']?.toString() ?? ''),
                        ],
                      ),
                      trailing: _buildTrailing(m, busy),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ----------------------------- downloads ------------------------------------
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with LangAware, SingleTickerProviderStateMixin {
  List<dynamic> _items = <dynamic>[];
  Timer? _timer;
  TabController? _tabs;
  bool _didInitTab = false;
  final TextEditingController _q = TextEditingController();
  Map<String, dynamic> _xfer = <String, dynamic>{};
  String? _error;
  DateTime? _prioPausedUntil;
  // hash → group number from the previous poll; populated after first fetch.
  Map<String, int>? _prevGroups;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _q.addListener(() => setState(() {}));
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs?.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> d = await Api.I.downloads();
      Map<String, dynamic> x = _xfer;
      try {
        x = await Api.I.transfer();
      } catch (_) {}
      if (!mounted) return;
      if (_prioPausedUntil != null && DateTime.now().isBefore(_prioPausedUntil!)) {
        // Priority change in flight — skip overwriting items so the optimistic
        // order is visible until qBittorrent has processed the reorder.
        setState(() { _xfer = x; _error = null; });
        return;
      }

      // Build current group snapshot and fire completion notifications.
      final Map<String, int> curr = <String, int>{};
      for (final dynamic raw in d) {
        final Map<String, dynamic> t = raw as Map<String, dynamic>;
        final String? hash = t['hash']?.toString();
        if (hash == null) continue;
        curr[hash] = _group(t['state']?.toString() ?? '');
      }
      if (_prevGroups != null) {
        // Fire once per torrent that crossed from active/queued (0-1) → done (2).
        for (final MapEntry<String, int> entry in curr.entries) {
          final int? prev = _prevGroups![entry.key];
          if (prev != null && prev <= 1 && entry.value == 2) {
            final Map<String, dynamic>? t = d
                .cast<Map<String, dynamic>>()
                .where((Map<String, dynamic> e) => e['hash'] == entry.key)
                .firstOrNull;
            final String name = t?['name']?.toString() ?? 'Download';
            _notifyDownloadDone(name);
          }
        }
      }
      _prevGroups = curr;

      setState(() {
        _items = d;
        _xfer = x;
        _error = null;
        // First time data arrives: open Active unless nothing is in progress.
        if (!_didInitTab && d.isNotEmpty) {
          _didInitTab = true;
          final bool hasActive = d.any((dynamic e) =>
              _group((e as Map<String, dynamic>)['state']?.toString() ?? '') <= 1);
          _tabs!.index = hasActive ? 0 : 1;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _eta(Object? s) {
    final int sec = (s is num) ? s.toInt() : 0;
    if (sec <= 0 || sec >= 8640000) return '∞';
    final int d = sec ~/ 86400;
    final int h = (sec % 86400) ~/ 3600;
    final int m = (sec % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  // Keep in sync with the gateway's ACTIVE_DOWNLOAD_STATES
  // (ai-gateway/app/services/qbittorrent.py). 'moving' and 'checkingResumeData' were
  // missing here, so a torrent still writing to disk during import was grouped as
  // finished and vanished from the active list while it was the thing filling the disk.
  static const Set<String> _activeStates = <String>{
    'downloading', 'forcedDL', 'metaDL', 'stalledDL', 'checkingDL', 'allocating',
    'moving', 'checkingResumeData'
  };
  static const Set<String> _seedingStates = <String>{
    'uploading', 'forcedUP', 'stalledUP'
  };
  static const Set<String> _failedStates = <String>{'error', 'missingFiles'};

  // qBittorrent state -> i18n key (resolved with tr() at render time so the
  // label follows the app language). Unmapped states fall back to the raw state.
  static const Map<String, String> _stateLabel = <String, String>{
    'downloading': 'stateDownloading',
    'forcedDL': 'stateDownloading',
    'stalledDL': 'stateStalledNoPeers',
    'metaDL': 'stateFetchingMetadata',
    'checkingDL': 'stateChecking',
    'allocating': 'stateAllocating',
    'queuedDL': 'stateQueued',
    'pausedDL': 'statePaused',
    'stoppedDL': 'stateStopped',
    'uploading': 'stateSeeding',
    'forcedUP': 'stateSeeding',
    'stalledUP': 'stateSeedingStalled',
    'checkingUP': 'stateChecking',
    'pausedUP': 'statePaused',
    'stoppedUP': 'stateStopped',
    'error': 'stateError',
    'missingFiles': 'stateMissingFiles',
    'moving': 'stateMoving',
    'checkingResumeData': 'stateChecking',
    'unknown': 'stateUnknown',
  };

  bool _isFailed(String s) => _failedStates.contains(s);

  int _group(String s) {
    if (_activeStates.contains(s)) return 0; // active downloads
    if (s == 'queuedDL') return 1;           // queued
    if (_isFailed(s)) return 3;              // failed (last, red)
    return 2;                                // finished / seeding / paused / stopped
  }

  // active=true -> downloading+queued; active=false -> finished+failed. Filtered by search.
  List<Map<String, dynamic>> _filtered(bool active) {
    final String ql = _q.text.trim().toLowerCase();
    final List<Map<String, dynamic>> items = _items
        .map((dynamic e) => e as Map<String, dynamic>)
        .where((Map<String, dynamic> t) {
      final int g = _group(t['state']?.toString() ?? '');
      if (active ? g > 1 : g <= 1) return false;
      if (ql.isEmpty) return true;
      return (t['name']?.toString() ?? '').toLowerCase().contains(ql);
    }).toList();
    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int ga = _group(a['state']?.toString() ?? '');
      final int gb = _group(b['state']?.toString() ?? '');
      if (ga != gb) return ga.compareTo(gb);
      if (ga == 0) {
        // Sort by qBittorrent priority (lower number = higher queue position).
        // Priority 0 means no queue limit — treat as lowest (sort to end).
        final int pa = (a['priority'] as num?)?.toInt() ?? 0;
        final int pb = (b['priority'] as num?)?.toInt() ?? 0;
        final int ea = pa == 0 ? 999999 : pa;
        final int eb = pb == 0 ? 999999 : pb;
        return ea.compareTo(eb);
      }
      return 0;
    });
    return items;
  }

  Future<void> _confirmCancel(Map<String, dynamic> t) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Stop download?'),
        content: Text('Remove "${t['name']}" and delete all partial files from disk?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final String? hash = t['hash']?.toString();
    if (hash == null) return;
    setState(() => _items.removeWhere(
        (dynamic e) => (e as Map<String, dynamic>)['hash'] == hash));
    try {
      await Api.I.cancelDownload(hash);
    } catch (_) {}
    _refresh();
  }

  /// Human-readable byte size: 354 MB, 35.6 GB, 1.2 TB.
  static String _fmtBytes(num bytes) {
    final double b = bytes.toDouble();
    if (b >= 1024 * 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
    }
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toStringAsFixed(0)} B';
  }

  String _subtitleStats(Map<String, dynamic> t) {
    final double pct = (t['progress'] as num?)?.toDouble() ?? 0;
    final String state = t['state']?.toString() ?? '';
    final String label = tr(_stateLabel[state] ?? state);
    if (_seedingStates.contains(state)) {
      final num up = (t['upspeed_mbs'] as num?) ?? 0;
      final num ratio = (t['ratio'] as num?) ?? 0;
      return '${pct.toStringAsFixed(1)}%  •  ↑ $up MB/s  •  ${tr('ratio')} ${ratio.toStringAsFixed(2)}  •  $label';
    }
    // Active downloads: append "downloaded / total" (e.g. 354 MB / 35.6 GB).
    final num sizeB = (t['size_bytes'] as num?) ?? 0;
    final num doneB = (t['downloaded_bytes'] as num?) ?? 0;
    final String size = sizeB > 0 ? '  •  ${_fmtBytes(doneB)} / ${_fmtBytes(sizeB)}' : '';
    return '${pct.toStringAsFixed(1)}%  •  ${t['dlspeed_mbs'] ?? 0} MB/s  •  '
        '${tr('eta')} ${_eta(t['eta_sec'])}  •  $label$size';
  }

  Widget _tile(Map<String, dynamic> t,
      {Key? key, int? dragIndex, bool cancellable = false}) {
    final double pct = (t['progress'] as num?)?.toDouble() ?? 0;
    final bool failed = _isFailed(t['state']?.toString() ?? '');
    final TextStyle? red = failed ? const TextStyle(color: Colors.redAccent) : null;
    return ListTile(
      key: key,
      leading: cancellable
          ? IconButton(
              icon: const Icon(Icons.stop_circle_outlined,
                  color: Colors.redAccent, size: 26),
              onPressed: () => _confirmCancel(t),
              tooltip: 'Stop download',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            )
          : null,
      title: Text(t['name']?.toString() ?? '',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: red),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 4),
          LinearProgressIndicator(value: pct / 100, color: failed ? Colors.redAccent : null),
          const SizedBox(height: 4),
          Text(_subtitleStats(t), style: red),
        ],
      ),
      trailing: dragIndex != null
          ? ReorderableDragStartListener(
              index: dragIndex,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            )
          : null,
    );
  }

  Future<void> _onReorder(List<Map<String, dynamic>> sorted, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final String? hash = sorted[oldIndex]['hash']?.toString();
    if (hash == null) return;
    setState(() {
      final Map<String, dynamic> item = sorted.removeAt(oldIndex);
      sorted.insert(newIndex, item);
      for (int i = 0; i < sorted.length; i++) {
        sorted[i]['priority'] = i + 1;
      }
      _prioPausedUntil = DateTime.now().add(const Duration(seconds: 5));
    });
    try {
      await Api.I.reorderTorrent(hash, oldIndex, newIndex);
    } catch (_) {}
  }

  Widget _list(List<Map<String, dynamic>> items,
      {bool reorderable = false, bool cancellable = false}) {
    if (items.isEmpty) {
      return ListView(children: <Widget>[
        const SizedBox(height: 120),
        Center(child: Text(tr('noResults'))),
      ]);
    }
    if (reorderable) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        onReorderItem: (int oldIndex, int newIndex) => _onReorder(items, oldIndex, newIndex),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) => _tile(
          items[i],
          key: ValueKey(items[i]['hash'] ?? i.toString()),
          dragIndex: i,
          cancellable: cancellable,
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (BuildContext context, int i) =>
          _tile(items[i], cancellable: cancellable),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _errorView(_error!, _refresh);
    }
    final List<Map<String, dynamic>> active = _filtered(true);
    final List<Map<String, dynamic>> finished = _filtered(false);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _q,
            decoration: InputDecoration(
                hintText: tr('search'), prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: <Widget>[
            Tab(text: '${tr('active')} (${active.length})'),
            Tab(text: '${tr('finished')} (${finished.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _list(active, reorderable: true, cancellable: true),
              RefreshIndicator(onRefresh: _refresh, child: _list(finished)),
            ],
          ),
        ),
        _speedBar(),
      ],
    );
  }

  Widget _speedBar() {
    final num dl = (_xfer['dl_mbs'] as num?) ?? 0;
    final num up = (_xfer['up_mbs'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.south, size: 16, color: Colors.lightBlueAccent),
            const SizedBox(width: 4),
            Text('$dl MB/s'),
          ]),
          Row(children: <Widget>[
            const Icon(Icons.north, size: 16, color: Colors.greenAccent),
            const SizedBox(width: 4),
            Text('$up MB/s'),
          ]),
        ],
      ),
    );
  }
}

// ----------------------------- library --------------------------------------
/// The language filter used by the Library tab. Top-level so it can be tested
/// directly rather than through a pumped widget and a faked gateway.
///
/// `lang` is 'all', 'cs' or 'en'. 'cs' means **available in Czech**, not "Czech and
/// nothing else": the question being answered is *do we have this in Czech*, and a
/// title that also has an English version still answers that yes.
///
/// An unrecognised value returns everything. The filter is restored from storage on
/// startup, and a stale or corrupted entry must not leave someone staring at an empty
/// library with no obvious way back.
List<dynamic> filterLibraryByLanguage(List<dynamic> items, String lang) {
  if (lang != 'cs' && lang != 'en') return items;
  final String key = lang == 'cs' ? 'on_disk_cs' : 'on_disk_en';
  return items.where((dynamic e) {
    final Map<String, dynamic>? m = e is Map<String, dynamic> ? e : null;
    return m != null && m[key] == true;
  }).toList();
}


/// The Library tab's language filter row.
///
/// Top-level rather than a method on the screen's state so its layout can be tested
/// at a real width, which is the whole reason it looks like this. The first version
/// put `tr('langCzech')` and `tr('langEnglish')` straight into the chips, which is
/// fine in English ("Czech", "English") and overflows the row in Czech, where the
/// same two words are "Čeština" and "Angličtina" — roughly twice as wide.
///
/// So nothing here is allowed to change width with the locale: the chips carry a flag
/// and a two-letter code, and the full language name moves to a tooltip. The count is
/// the one variable-width piece left, so it gets the leftover space and an ellipsis
/// rather than a fixed slot it can overrun.
class LanguageFilterBar extends StatelessWidget {
  const LanguageFilterBar({
    super.key,
    required this.lang,
    required this.shown,
    required this.total,
    required this.onChanged,
  });

  /// 'all' | 'cs' | 'en'
  final String lang;
  final int shown;
  final int total;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<List<String>> options = <List<String>>[
      // code, short label, flag, tooltip
      <String>['all', tr('langAll'), '', tr('langAll')],
      <String>['cs', 'CZ', '\u{1F1E8}\u{1F1FF}', tr('langCzech')],
      <String>['en', 'EN', '\u{1F1EC}\u{1F1E7}', tr('langEnglish')],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: <Widget>[
          for (final List<String> opt in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: opt[3],
                child: FilterChip(
                  selected: lang == opt[0],
                  onSelected: (_) => onChanged(opt[0]),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  label: Text(opt[2].isEmpty ? opt[1] : '${opt[2]} ${opt[1]}',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          // Expanded, not Spacer + a fixed Text: this both pushes the count to the
          // right and lets it shrink, so a long translation ellipses instead of
          // overflowing the row.
          if (lang != 'all')
            Expanded(
              child: Text(
                tr('langFilterCount')
                    .replaceAll('{n}', '$shown')
                    .replaceAll('{total}', '$total'),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}


class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with LangAware {
  String _type = 'movie';
  final TextEditingController _q = TextEditingController();
  List<dynamic> _items = <dynamic>[];
  Map<String, dynamic> _disk = <String, dynamic>{};
  String? _error;

  /// Language filter: 'all' | 'cs' | 'en'. Persisted, because the people who care
  /// about it care about it permanently — someone who only ever wants to know what
  /// exists in Czech should not have to re-pick it on every app start.
  static const String _langFilterKey = 'libraryLangFilter';
  String _lang = 'all';

  @override
  void initState() {
    super.initState();
    _restoreLangFilter();
    _refresh();
  }

  Future<void> _restoreLangFilter() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_langFilterKey);
      // Guard the stored value: an older or corrupted entry must not leave the list
      // filtering on something the UI has no chip for, which would look like an
      // empty library with no way back.
      if (saved != null && <String>['all', 'cs', 'en'].contains(saved)) {
        if (mounted) setState(() => _lang = saved);
      }
    } catch (_) {
      // Storage unavailable (private mode, cleared data) — 'all' is the safe default.
    }
  }

  Future<void> _setLangFilter(String value) async {
    setState(() => _lang = value);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_langFilterKey, value);
    } catch (_) {
      // The filter still applies for this session even if it cannot be remembered.
    }
  }

  List<dynamic> get _visibleItems => filterLibraryByLanguage(_items, _lang);

  Widget _langFilterBar() => LanguageFilterBar(
        lang: _lang,
        shown: _visibleItems.length,
        total: _items.length,
        onChanged: _setLangFilter,
      );

  Future<void> _refresh() async {
    try {
      final List<dynamic> r = await Api.I.library(_type, _q.text.trim());
      Map<String, dynamic> disk = _disk;
      try {
        disk = await Api.I.diskspace();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _items = r;
          _disk = disk;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _freeStr(double gb) {
    if (gb >= 1000) return '${(gb / 1000).toStringAsFixed(2)} TB';
    if (gb >= 1) return '${gb.toStringAsFixed(0)} GB';
    return '${(gb * 1000).toStringAsFixed(0)} MB';
  }

  Color _diskColor(double pct) {
    if (pct > 85) return Colors.red;
    if (pct > 80) return Colors.orange;
    if (pct > 70) return Colors.yellow.shade700;
    return Colors.green;
  }

  Widget _diskBar() {
    final double pct = (_disk['used_pct'] as num?)?.toDouble() ?? 0;
    final double free = (_disk['free_gb'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('${pct.toStringAsFixed(0)}% ${tr('storageUsedSuffix')}',
                  style: const TextStyle(fontSize: 12)),
              Text('${_freeStr(free)} ${tr('free')}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                value: pct / 100, minHeight: 6, color: _diskColor(pct)),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            content: Text(tr('deleteConfirm')),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('delete'))),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final double freeBefore = (_disk['free_gb'] as num?)?.toDouble() ?? 0;
    try {
      await Api.I.deleteItem(_type, m['id'] as int);
      await _refresh();
      // Radarr/Sonarr delete the files asynchronously: the API returns before the
      // bytes are actually gone, so the refresh above usually still reports the OLD
      // free space. Keep re-reading it in the background until it moves, so the disk
      // bar reflects the delete without the user pulling to refresh.
      unawaited(_pollDiskSpace(freeBefore));
    } catch (_) {}
  }

  /// Re-read /diskspace until the reported free space changes (or we give up).
  /// Cheap: a handful of small GETs, and it stops as soon as the value moves.
  Future<void> _pollDiskSpace(double freeBefore) async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      try {
        final Map<String, dynamic> d = await Api.I.diskspace();
        final double now = (d['free_gb'] as num?)?.toDouble() ?? 0;
        if (!mounted) return;
        setState(() => _disk = d);
        // A delete only ever frees space; stop as soon as we see it.
        if (now > freeBefore) return;
      } catch (_) {
        return; // transient failure — the next manual refresh will correct it
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _errorView(_error!, _refresh);
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _q,
                  onSubmitted: (_) => _refresh(),
                  decoration: InputDecoration(
                      hintText: tr('search'), prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'movie', label: Text(tr('movie'))),
                  ButtonSegment<String>(value: 'tv', label: Text(tr('tv'))),
                ],
                selected: <String>{_type},
                onSelectionChanged: (Set<String> s) {
                  setState(() => _type = s.first);
                  _refresh();
                },
              ),
            ],
          ),
        ),
        _langFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _visibleItems.isEmpty && _items.isNotEmpty
                ? ListView(
                    // A plain Center would not scroll, and RefreshIndicator needs a
                    // scrollable child for pull-to-refresh to keep working here.
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                        child: Column(children: <Widget>[
                          const Icon(Icons.filter_alt_off, size: 40, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(tr('langFilterEmpty'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => _setLangFilter('all'),
                            child: Text(tr('langAll')),
                          ),
                        ]),
                      ),
                    ],
                  )
                : ListView.builder(
              itemCount: _visibleItems.length,
              itemBuilder: (BuildContext context, int i) {
                final Map<String, dynamic> m = _visibleItems[i] as Map<String, dynamic>;
                final bool hasFile = m['hasFile'] == true;
                final double sizeGb = (m['size_gb'] as num?)?.toDouble() ?? 0;
                final String yearSize = <String>[
                  m['year']?.toString() ?? '',
                  if (sizeGb > 0) '${sizeGb.toStringAsFixed(1)} GB',
                ].where((String s) => s.isNotEmpty).join('  •  ');
                return ListTile(
                  onTap: () => Navigator.push<void>(context,
                      MaterialPageRoute<void>(
                          builder: (_) => DetailScreen(
                              item: <String, dynamic>{...m, 'type': _type}))),
                  leading: PosterImage(rowPosterUrl(m)),
                  title: Text(m['title']?.toString() ?? ''),
                  subtitle: Row(
                    children: <Widget>[
                      Icon(hasFile ? Icons.check_circle : Icons.hourglass_empty,
                          size: 14, color: hasFile ? Colors.green : Colors.grey),
                      const SizedBox(width: 4),
                      Text(yearSize),
                      // Same flags the search results use, so what the filter selects
                      // on is visible on the row rather than implied.
                      if (m['on_disk_en'] == true || m['on_disk_cs'] == true) ...<Widget>[
                        const SizedBox(width: 6),
                        if (m['on_disk_en'] == true)
                          const Text('\u{1F1EC}\u{1F1E7}', style: TextStyle(fontSize: 12)),
                        if (m['on_disk_en'] == true && m['on_disk_cs'] == true)
                          const SizedBox(width: 2),
                        if (m['on_disk_cs'] == true)
                          const Text('\u{1F1E8}\u{1F1FF}', style: TextStyle(fontSize: 12)),
                      ],
                      if (missingEpisodeCount(m) != null) ...<Widget>[
                        const SizedBox(width: 6),
                        IncompleteBadge(item: m),
                      ],
                    ],
                  ),
                  trailing: Api.I.isAdmin
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(m),
                        )
                      : null,
                );
              },
            ),
          ),
        ),
        if (((_disk['total_gb'] as num?) ?? 0) > 0) _diskBar(),
      ],
    );
  }
}

// ----------------------------- Plex sessions (admin) ------------------------
// ----------------------------- Help / connect --------------------------------
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('helpConnect')),
          bottom: TabBar(tabs: <Widget>[
            Tab(icon: const Icon(Icons.home), text: tr('helpHomeNetwork')),
            Tab(icon: const Icon(Icons.public), text: tr('helpAnywhere')),
          ]),
        ),
        body: TabBarView(children: <Widget>[
          _LocalTab(),
          _RemoteTab(),
        ]),
      ),
    );
  }
}

class _LocalTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double bottomPad = MediaQuery.of(context).viewPadding.bottom + 24;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      children: <Widget>[
        _AddressCard(
          address: 'http://192.168.50.141:8096',
          icon: Icons.home_outlined,
          color: cs.primaryContainer,
          onColor: cs.onPrimaryContainer,
        ),
        const SizedBox(height: 16),
        _HelpSection(icon: Icons.tv, title: tr('helpTvTitle'), steps: <String>[
          tr('helpTvStep1'), tr('helpTvStep2'), tr('helpTvStep3'),
          tr('helpTvStep4local'), tr('helpTvStep5'),
        ]),
        const SizedBox(height: 12),
        _HelpSection(icon: Icons.phone_android, title: tr('helpMobileTitle'), steps: <String>[
          tr('helpMobileStep1'), tr('helpMobileStep2local'), tr('helpMobileStep3'),
        ]),
        const SizedBox(height: 12),
        _JellyfinDownloadCard(),
        const SizedBox(height: 12),
        _HelpSection(icon: Icons.open_in_browser, title: tr('helpBrowserTitle'), steps: <String>[
          tr('helpBrowserStep1'), tr('helpBrowserStep2local'), tr('helpBrowserStep3'),
        ]),
      ],
    );
  }
}

class _RemoteTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double bottomPad = MediaQuery.of(context).viewPadding.bottom + 24;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      children: <Widget>[
        _AddressCard(
          address: 'https://jellyfin.mattyzem.com',
          icon: Icons.public,
          color: cs.tertiaryContainer,
          onColor: cs.onTertiaryContainer,
        ),
        const SizedBox(height: 12),
        _HelpSection(icon: Icons.tv, title: tr('helpTvTitle'), steps: <String>[
          tr('helpTvStep1'), tr('helpTvStep2'), tr('helpTvStep3'),
          tr('helpTvStep4remote'), tr('helpTvStep5'),
        ]),
        const SizedBox(height: 12),
        _HelpSection(icon: Icons.phone_android, title: tr('helpMobileTitle'), steps: <String>[
          tr('helpMobileStep1'), tr('helpMobileStep2remote'), tr('helpMobileStep3'),
        ]),
        const SizedBox(height: 12),
        _JellyfinDownloadCard(),
        const SizedBox(height: 12),
        _HelpSection(icon: Icons.open_in_browser, title: tr('helpBrowserTitle'), steps: <String>[
          tr('helpBrowserStep1'), tr('helpBrowserStep2remote'), tr('helpBrowserStep3'),
        ]),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.icon, required this.color, required this.onColor});
  final String address;
  final IconData icon;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(Icons.dns_outlined, color: onColor),
              const SizedBox(width: 8),
              Text(tr('helpServerAddr'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: onColor)),
            ]),
            const SizedBox(height: 10),
            Row(children: <Widget>[
              Icon(icon, size: 16, color: onColor.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(address,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: onColor, fontFamily: 'monospace')),
            ]),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.url});
  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: <Widget>[
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Colors.blueAccent,
                  decoration: TextDecoration.underline)),
        ]),
      ),
    );
  }
}

class _JellyfinDownloadCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.download_outlined, size: 20),
              const SizedBox(width: 8),
              Text(tr('helpJellyfinDownload'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            _LinkRow(
              icon: Icons.android,
              label: tr('helpJellyfinAndroid'),
              url: 'https://play.google.com/store/apps/details?id=org.jellyfin.mobile',
            ),
            const SizedBox(height: 8),
            _LinkRow(
              icon: Icons.phone_iphone,
              label: tr('helpJellyfinIos'),
              url: 'https://apps.apple.com/app/jellyfin-mobile/id1480192618',
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.icon, required this.title, required this.steps});
  final IconData icon;
  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 10),
            ...steps.asMap().entries.map((MapEntry<int, String> e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${e.key + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ----------------------------- Sessions (admin) ------------------------------
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});
  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> with LangAware {
  List<dynamic> _sessions = <dynamic>[];
  Timer? _timer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> s = await Api.I.sessions();
      if (mounted) {
        setState(() {
          _sessions = s;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String _ago(int unixSec) {
    if (unixSec <= 0) return '';
    final int diffSec =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - unixSec;
    if (diffSec < 90) return '${diffSec}s ago';
    final int m = diffSec ~/ 60;
    if (m < 90) return '${m}m ago';
    final int h = diffSec ~/ 3600;
    if (h < 48) return '${h}h ago';
    return '${diffSec ~/ 86400}d ago';
  }

  Future<void> _terminate(String source, String sessionKey) async {
    try {
      await Api.I.terminateSession(source, sessionKey);
      await _refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('mediaSessions'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(child: Text(tr('noSessions')))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 16),
                    itemCount: _sessions.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Map<String, dynamic> s = _sessions[i] as Map<String, dynamic>;
                      final double pct = (s['progress_pct'] as num?)?.toDouble() ?? 0;
                      final bool playing = s['state'] == 'playing';
                      final num? bw = s['bandwidth_kbps'] as num?;
                      final String loc = (s['location'] ?? '').toString().toUpperCase();
                      final bool transcode = s['transcode'] == true;
                      final int lastViewedAt = (s['last_viewed_at'] as num?)?.toInt() ?? 0;
                      final String ago = _ago(lastViewedAt);
                      final bool stale = lastViewedAt > 0 &&
                          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - lastViewedAt) > 300;
                      final String? sessionKey = s['session_key']?.toString();
                      final String source = (s['source'] ?? 'plex').toString();
                      final bool isPlex = source == 'plex';
                      return ListTile(
                        leading: Icon(playing ? Icons.play_circle : Icons.pause_circle,
                            color: stale
                                ? Colors.grey
                                : playing
                                    ? Colors.green
                                    : Colors.orangeAccent),
                        title: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text('${s['user'] ?? '?'} — ${s['title'] ?? ''}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: (isPlex ? Colors.orange : Colors.purple)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4)),
                              child: Text(isPlex ? 'PLEX' : 'JELLYFIN',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isPlex ? Colors.orange : Colors.purple)),
                            ),
                            if (stale)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text('stale',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.orange)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                                value: pct / 100,
                                color: stale ? Colors.grey : null),
                            const SizedBox(height: 4),
                            Text(<String>[
                              '${pct.toStringAsFixed(0)}%',
                              if (ago.isNotEmpty) ago,
                              if (s['player'] != null) s['player'].toString(),
                              if (s['address'] != null)
                                '${s['address']}${loc.isNotEmpty ? ' ($loc)' : ''}',
                              if (bw != null)
                                '${(bw / 1000).toStringAsFixed(1)} Mbit/s',
                              transcode ? tr('transcode') : tr('direct'),
                            ].join('  •  ')),
                          ],
                        ),
                        trailing: sessionKey != null
                            ? IconButton(
                                icon: const Icon(Icons.cancel_outlined,
                                    color: Colors.redAccent),
                                tooltip: 'Terminate session',
                                onPressed: () => _terminate(source, sessionKey),
                              )
                            : null,
                      );
                    },
                  ),
                ),
    );
  }
}

// ----------------------------- User management (admin) ----------------------
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with LangAware {
  List<dynamic> _users = <dynamic>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> u = await Api.I.listUsers();
      if (mounted) setState(() { _users = u; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _openDialog({Map<String, dynamic>? existing}) async {
    final bool isEdit = existing != null;
    final TextEditingController nameCtrl =
        TextEditingController(text: existing?['username']?.toString() ?? '');
    final TextEditingController dispCtrl =
        TextEditingController(text: existing?['displayname']?.toString() ?? '');
    final TextEditingController passCtrl = TextEditingController();
    bool isAdmin = (existing?['groups'] as List<dynamic>?)?.contains('admins') ?? false;
    bool isAiAccess = (existing?['is_ai_access'] as bool?) ?? false;
    final bool? initialDownload =
        isEdit ? (existing['can_download'] as bool?) : true;
    bool canDownload = initialDownload ?? true;
    bool downloadTouched = false;
    bool saving = false;
    String? errorMsg;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter ss) => AlertDialog(
          title: Text(isEdit ? tr('editUser') : tr('addUser')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!isEdit)
                  TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(labelText: tr('username')),
                      onChanged: (_) { if (errorMsg != null) ss(() => errorMsg = null); }),
                const SizedBox(height: 8),
                TextField(
                    controller: dispCtrl,
                    decoration: InputDecoration(labelText: tr('displayName')),
                    onChanged: (_) { if (errorMsg != null) ss(() => errorMsg = null); }),
                const SizedBox(height: 8),
                TextField(
                    controller: passCtrl,
                    decoration: InputDecoration(
                        labelText: isEdit ? tr('newPassword') : tr('password')),
                    obscureText: true,
                    onChanged: (_) { if (errorMsg != null) ss(() => errorMsg = null); }),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('isAdmin')),
                  value: isAdmin,
                  onChanged: saving ? null : (bool? v) => ss(() => isAdmin = v ?? false),
                ),
                if (Api.I.isSuperadmin)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('AI access'),
                    value: isAiAccess,
                    onChanged: saving ? null : (bool? v) => ss(() => isAiAccess = v ?? false),
                  ),
                DownloadPermissionTile(
                  value: canDownload,
                  unknown: isEdit && initialDownload == null && !downloadTouched,
                  onChanged: saving
                      ? null
                      : (bool v) => ss(() {
                            canDownload = v;
                            downloadTouched = true;
                          }),
                ),
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMsg!,
                      style: TextStyle(
                          color: Theme.of(ctx2).colorScheme.error, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx2).pop(false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      ss(() => saving = true);
                      try {
                        if (isEdit) {
                          await Api.I.updateUser(
                            existing?['username']?.toString() ?? '',
                            displayname: dispCtrl.text.trim(),
                            password: passCtrl.text.isEmpty ? null : passCtrl.text,
                            isAdmin: isAdmin,
                            isAiAccess: isAiAccess,
                            canDownload: downloadToSend(
                                isEdit: true,
                                initial: initialDownload,
                                current: canDownload,
                                touched: downloadTouched),
                          );
                        } else {
                          await Api.I.createUser(
                            username: nameCtrl.text.trim(),
                            password: passCtrl.text,
                            displayname: dispCtrl.text.trim(),
                            isAdmin: isAdmin,
                            isAiAccess: isAiAccess,
                            canDownload: canDownload,
                          );
                        }
                        if (ctx2.mounted) Navigator.of(ctx2).pop(true);
                      } catch (e) {
                        final String detail = Api.errorDetail(e);
                        final String msg = detail.isNotEmpty ? detail : tr('error');
                        if (ctx2.mounted) ss(() { saving = false; errorMsg = msg; });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('save')),
            ),
          ],
        ),
      ),
    );

    if (saved == true) await _refresh();
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('deleteUser')),
        content: Text(u['username']?.toString() ?? ''),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('delete'))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Api.I.deleteUser(u['username']?.toString() ?? '');
        await _refresh();
      } catch (e) {
        final String msg = Api.errorDetail(e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg.isNotEmpty ? msg : tr('error'))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('userManagement'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _openDialog,
        child: const Icon(Icons.person_add),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(child: Text(tr('noUsers')))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 16),
                    itemCount: _users.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Map<String, dynamic> u = _users[i] as Map<String, dynamic>;
                      final bool admin =
                          (u['groups'] as List<dynamic>?)?.contains('admins') ?? false;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text((u['displayname']?.toString() ??
                                  u['username']?.toString() ??
                                  '?')
                              .substring(0, 1)
                              .toUpperCase()),
                        ),
                        title: Text(u['displayname']?.toString() ??
                            u['username']?.toString() ??
                            '?'),
                        subtitle: Text(u['username']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // Only the exception is marked: downloading is the default.
                            if (u['can_download'] == false)
                              Tooltip(
                                message: tr('noDownloads'),
                                child: Icon(Icons.file_download_off_outlined,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.outline),
                              ),
                            if (admin)
                              Chip(
                                label: Text(tr('admin'),
                                    style: const TextStyle(fontSize: 11)),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openDialog(existing: u),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(u),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ----------------------------- AI chats list (superadmin) -------------------
class AiChatsListScreen extends StatefulWidget {
  const AiChatsListScreen({super.key});
  @override
  State<AiChatsListScreen> createState() => _AiChatsListScreenState();
}

class _AiChatsListScreenState extends State<AiChatsListScreen> with LangAware {
  List<dynamic> _chats = <dynamic>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<dynamic> chats = await Api.I.listChats();
      if (mounted) setState(() { _chats = chats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newChat() async {
    final Map<String, dynamic> chat = await Api.I.createChat();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AiChatScreen(chatId: chat['id'] as String,
            initialTitle: chat['title'] as String)));
    await _load();
  }

  Future<void> _rename(Map<String, dynamic> chat) async {
    final TextEditingController ctrl =
        TextEditingController(text: chat['title'] as String? ?? '');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('renameChat')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('save'))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await Api.I.renameChat(chat['id'] as String, ctrl.text.trim());
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> chat) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('deleteChat')),
        content: Text(chat['title'] as String? ?? ''),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('delete'))),
        ],
      ),
    );
    if (ok == true) {
      await Api.I.deleteChat(chat['id'] as String);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: <Widget>[
          const Icon(Icons.smart_toy_outlined, size: 20),
          const SizedBox(width: 8),
          Text(tr('aiChats')),
        ]),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.add),
        label: Text(tr('newChat')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.chat_bubble_outline,
                          size: 56, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(tr('noChats'),
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Map<String, dynamic> chat =
                        _chats[i] as Map<String, dynamic>;
                    final bool unread = (chat['has_unread'] as int? ?? 0) == 1;
                    final String title = chat['title'] as String? ?? 'Chat';
                    final ColorScheme cs = Theme.of(context).colorScheme;
                    return ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          const Icon(Icons.chat_bubble_outline),
                          if (unread)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: unread ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        (chat['updated_at'] as String? ?? '').replaceFirst('T', ' ').substring(0, 16),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => AiChatScreen(
                                chatId: chat['id'] as String,
                                initialTitle: title)));
                        await _load();
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (String v) async {
                          if (v == 'rename') await _rename(chat);
                          if (v == 'delete') await _delete(chat);
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                              value: 'rename', child: Text(tr('renameChat'))),
                          PopupMenuItem<String>(
                              value: 'delete', child: Text(tr('deleteChat'))),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ----------------------------- AI chat screen (one conversation) -------------
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, required this.chatId, required this.initialTitle});
  final String chatId;
  final String initialTitle;
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with LangAware {
  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  bool _loading = true;
  late String _title;

  @override
  void initState() {
    super.initState();
    _title = widget.initialTitle;
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> data = await Api.I.getChat(widget.chatId);
      final List<dynamic> msgs = data['messages'] as List<dynamic>? ?? <dynamic>[];
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(msgs.cast<Map<String, dynamic>>());
          _title = (data['chat'] as Map<String, dynamic>?)?['title'] as String? ?? _title;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add(<String, dynamic>{'role': 'user', 'content': text});
      _busy = true;
    });
    _scrollToBottom();
    try {
      final Map<String, dynamic> reply =
          await Api.I.sendChatMessage(widget.chatId, text);
      if (mounted) {
        setState(() {
          _messages.add(reply);
          // Auto-title: update AppBar if the gateway generated a name.
          final String? newTitle = reply['new_title'] as String?;
          if (newTitle != null && newTitle.isNotEmpty) _title = newTitle;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(
            <String, dynamic>{'role': 'assistant', 'content': 'Error: $e'}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final bool isUser = m['role'] == 'user';
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          m['content']?.toString() ?? '',
          style: TextStyle(color: isUser ? cs.onPrimary : cs.onSurface),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16),
          ),
        ),
        child: const SizedBox(width: 48, height: 12, child: LinearProgressIndicator()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      // SafeArea keeps the input row above the Android gesture/nav bar
      // (viewInsets below only accounts for the keyboard, not system nav).
      body: SafeArea(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Expanded(
                  child: _messages.isEmpty && !_busy
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.smart_toy_outlined,
                                    size: 56,
                                    color: Theme.of(context).colorScheme.primary),
                                const SizedBox(height: 16),
                                Text(tr('aiAssistant'),
                                    style: const TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Opacity(
                                  opacity: 0.6,
                                  child: Text(tr('aiEmptyHint'),
                                      textAlign: TextAlign.center),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          itemCount: _messages.length + (_busy ? 1 : 0),
                          itemBuilder: (BuildContext context, int i) {
                            if (i == _messages.length) return _typingBubble();
                            return _bubble(_messages[i]);
                          },
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      12, 8, 12, 12 + MediaQuery.of(context).viewInsets.bottom),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: !_busy,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: tr('aiHint'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

// ----------------------------- Speed test (admin) ---------------------------
class SpeedtestScreen extends StatefulWidget {
  const SpeedtestScreen({super.key});
  @override
  State<SpeedtestScreen> createState() => _SpeedtestScreenState();
}

class _SpeedtestScreenState extends State<SpeedtestScreen> with LangAware {
  Map<String, dynamic>? _result;
  bool _running = false;
  String? _error;

  Future<void> _run() async {
    setState(() { _running = true; _error = null; _result = null; });
    try {
      final Map<String, dynamic> r = await Api.I.speedtest();
      if (mounted) setState(() { _result = r; _running = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _running = false; });
    }
  }

  Widget _statRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: <Widget>[
          const Icon(Icons.network_check, size: 20),
          const SizedBox(width: 8),
          Text(tr('speedtest')),
        ]),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_running) ...<Widget>[
                const SizedBox(
                  width: 72, height: 72,
                  child: CircularProgressIndicator(strokeWidth: 5)),
                const SizedBox(height: 24),
                Text(tr('speedtestRunning'), textAlign: TextAlign.center),
              ] else if (_result != null) ...<Widget>[
                _statRow(Icons.south, tr('downloadSpeed'),
                    '${_result!['download_mbps']} Mbit/s', Colors.lightBlueAccent),
                const Divider(),
                _statRow(Icons.north, tr('uploadSpeed'),
                    '${_result!['upload_mbps']} Mbit/s', Colors.greenAccent),
                const Divider(),
                _statRow(Icons.timer_outlined, tr('ping'),
                    '${_result!['ping_ms']} ms', Colors.orangeAccent),
                const Divider(),
                if ((_result!['server'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.dns_outlined, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${tr('testServer')}: ${_result!['server']}')),
                      ],
                    ),
                  ),
                if ((_result!['isp'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.router_outlined, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(child: Text('${tr('isp')}: ${_result!['isp']}')),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _run,
                  child: Text(tr('runSpeedtest')),
                ),
              ] else ...<Widget>[
                const Icon(Icons.network_check, size: 72, color: Colors.grey),
                const SizedBox(height: 24),
                if (_error != null) ...<Widget>[
                  Text(_error!, style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(tr('runSpeedtest')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Health Check screen (admin-only)
// ─────────────────────────────────────────────────────────────────────────────

class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({super.key});
  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> with LangAware {
  Map<String, dynamic>? _report;
  bool _running = false;
  bool _loading = true;
  String? _error;
  String? _swapping; // key for in-progress swap: "${type}_${itemId}_${queueItemId}"
  String? _resolving; // message-key of the item currently being AI-resolved

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await Api.I.healthReport();
      if (mounted) setState(() { _report = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _run() async {
    setState(() { _running = true; _error = null; });
    try {
      final Map<String, dynamic> r = await Api.I.triggerHealthCheck();
      if (mounted) setState(() { _report = r; _running = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _running = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: <Widget>[
          const Icon(Icons.health_and_safety_outlined, size: 20),
          const SizedBox(width: 8),
          Text(tr('healthCheck')),
        ]),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: tr('runHealthCheck'),
            onPressed: _running ? null : _run,
          ),
        ],
      ),
      body: (_loading || _running)
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_running ? tr('healthCheckRunning') : ''),
            ]))
          : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center),
      ));
    }

    if (_report == null || !_report!.containsKey('checked_at')) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Icon(Icons.health_and_safety_outlined, size: 72, color: Colors.grey),
        const SizedBox(height: 16),
        Text(tr('healthCheckNever'), style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.play_arrow),
          label: Text(tr('runHealthCheck')),
        ),
      ]));
    }

    final List<dynamic> issues = (_report!['issues'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> warnings = (_report!['warnings'] as List<dynamic>?) ?? <dynamic>[];
    final String? lastRun = _report!['checked_at'] as String?;
    final num? durationSec = _report!['duration_s'] as num?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(children: <Widget>[
          if (issues.isEmpty && warnings.isEmpty)
            _chip(Icons.check_circle, tr('healthCheckOk'), Colors.green)
          else if (issues.isNotEmpty) ...<Widget>[
            _chip(Icons.error, '${issues.length} ${tr('healthCheckIssues')}',
                Colors.redAccent),
            if (warnings.isNotEmpty) const SizedBox(width: 8),
          ],
          if (warnings.isNotEmpty)
            _chip(Icons.warning_amber, '${warnings.length} ${tr('healthCheckWarnings')}',
                Colors.amber),
        ]),
        const SizedBox(height: 4),
        if (lastRun != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${tr('healthCheckLastRun')}: ${_fmtTs(lastRun)}'
              '${durationSec != null ? '  •  ${tr('healthCheckDuration')}: ${durationSec.toStringAsFixed(1)}s' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),

        if (issues.isNotEmpty) ...<Widget>[
          _sectionHeader(tr('healthCheckIssues'), theme, color: Colors.redAccent),
          ...issues.map<Widget>((dynamic i) => _issueCard(i as Map<String, dynamic>)),
        ],

        if (warnings.isNotEmpty) ...<Widget>[
          _sectionHeader(tr('healthCheckWarnings'), theme, color: Colors.amber),
          ...warnings.map<Widget>((dynamic w) => _issueCard(w as Map<String, dynamic>, isWarning: true)),
        ],

        if (issues.isEmpty && warnings.isEmpty &&
            ((_report!['sonarr_health'] as List<dynamic>?) ?? <dynamic>[]).isEmpty &&
            ((_report!['radarr_health'] as List<dynamic>?) ?? <dynamic>[]).isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Text(tr('healthCheckOk'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
          )),

        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: _run,
          child: Text(tr('runHealthCheck')),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.12),
      padding: EdgeInsets.zero,
    );
  }

  Widget _sectionHeader(String title, ThemeData theme, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          )),
    );
  }

  Future<void> _swap(
      String type, int itemId, int queueItemId, Map<String, dynamic> alt) async {
    final String key = '${type}_${itemId}_$queueItemId';
    setState(() => _swapping = key);
    try {
      await Api.I.swapTorrent(
        type: type,
        itemId: itemId,
        queueItemId: queueItemId,
        guid: alt['guid'] as String,
        indexerId: alt['indexer_id'] as int,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('swapStarted'))));
        await _load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('error'))));
      }
    } finally {
      if (mounted) setState(() => _swapping = null);
    }
  }

  Future<void> _resolve(Map<String, dynamic> item) async {
    final String key = item['message'] as String? ?? item.toString();
    setState(() => _resolving = key);
    try {
      final Map<String, dynamic> result = await Api.I.healthResolve(item);
      if (!mounted) return;
      final bool ok = result['ok'] == true;
      final String msg = result['message'] as String? ?? '';
      if (ok) {
        await _run();
        if (mounted && msg.isNotEmpty) {
          final String display =
              msg.length > 120 ? '${msg.substring(0, 117)}...' : msg;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(display), duration: const Duration(seconds: 8)));
        }
      } else {
        final String msg = result['message'] as String? ?? 'Could not resolve.';
        setState(() => _resolving = null);
        await showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(tr('aiFixFailed')),
            content: Text(msg),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('ok')),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('error'))));
      }
    } finally {
      if (mounted) setState(() => _resolving = null);
    }
  }

  Widget _issueCard(Map<String, dynamic> item, {bool isWarning = false}) {
    final String category = item['category'] as String? ?? '';
    if (category == 'stalled') return _stalledCard(item);

    final Color color = isWarning ? Colors.amber : Colors.redAccent;
    final String message = item['message'] as String? ?? '';
    final bool isMissingEpisodes = category == 'missing_episodes';
    final bool missingStale = isMissingEpisodes && item['stale'] == true;
    final bool canFix = category != 'check_error' && (!isMissingEpisodes || missingStale);
    final bool isResolving = _resolving == message;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(isWarning ? Icons.warning_amber : Icons.error_outline, color: color),
        title: Text(_categoryLabel(category),
            style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (message.isNotEmpty)
              Text(message, style: const TextStyle(fontSize: 12)),
            if (isMissingEpisodes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  missingStale
                      ? tr('healthCheckMissingEpisodesStale')
                      : tr('healthCheckMissingEpisodesNote'),
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: color.withValues(alpha: 0.65)),
                ),
              ),
          ],
        ),
        trailing: canFix
            ? (isResolving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: tr('aiFix'),
                    onPressed: () => _resolve(item),
                  ))
            : null,
      ),
    );
  }

  Widget _stalledCard(Map<String, dynamic> item) {
    final String message = item['message'] as String? ?? '';
    final Map<String, dynamic>? alt = item['alternative'] as Map<String, dynamic>?;
    final int? queueItemId = item['queue_item_id'] as int?;
    final List<dynamic> queueItemIds =
        (item['queue_item_ids'] as List<dynamic>?) ?? <dynamic>[];
    final String? itemType = item['item_type'] as String?;
    final int? itemId = item['item_id'] as int?;
    final String swapKey = '${itemType}_${itemId}_$queueItemId';
    final bool swapping = _swapping == swapKey;
    final int groupCount = queueItemIds.length > 1 ? queueItemIds.length : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.amber.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.hourglass_disabled, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(tr('healthCheckStalled'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.amber)),
              if (groupCount > 0) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$groupCount items',
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: Colors.amber)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            if (alt != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: <Widget>[
                  const Icon(Icons.swap_horiz, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(alt['title'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(
                          '${alt['indexer'] ?? ''} · '
                          '${alt['seeders'] ?? 0} seeds · '
                          '${alt['size_gb'] ?? 0} GB · '
                          '${alt['resolution'] ?? 0}p',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  swapping
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: (itemType != null && itemId != null && queueItemId != null)
                              ? () => _swap(itemType, itemId, queueItemId, alt)
                              : null,
                          child: Text(tr('swap')),
                        ),
                ]),
              )
            else
              Text(tr('noAlternative'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _resolving == message
                  ? Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 6),
                      Text(tr('aiFixing'),
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ])
                  : TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: swapping ? null : () => _resolve(item),
                      icon: const Icon(Icons.auto_fix_high, size: 15),
                      label: Text(groupCount > 0
                          ? '${tr('aiFix')} ($groupCount)'
                          : tr('aiFix')),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'missing_file':       return tr('healthCheckMissing');
      case 'suspicious_size':
      case 'small_file':         return tr('healthCheckSmall');
      case 'not_imported':       return tr('healthCheckNotImported');
      case 'torrent_error':      return tr('healthCheckQbtError');
      case 'stalled':            return tr('healthCheckStalled');
      case 'sonarr':             return tr('healthCheckSonarr');
      case 'radarr':             return tr('healthCheckRadarr');
      case 'missing_episodes':   return tr('healthCheckMissingEpisodes');
      case 'large_untracked':       return tr('healthCheckLargeUntracked');
      case 'unregistered_media':    return tr('healthCheckUnregistered');
      default:                   return category;
    }
  }

  String _fmtTs(String iso) {
    try {
      final DateTime dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera list screen (superadmin-only)
// ─────────────────────────────────────────────────────────────────────────────

class CameraListScreen extends StatefulWidget {
  const CameraListScreen({super.key});
  @override
  State<CameraListScreen> createState() => _CameraListScreenState();
}

class _CameraListScreenState extends State<CameraListScreen> with LangAware {
  List<Map<String, dynamic>> _cameras = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final List<Map<String, dynamic>> cams = await Api.I.listCameras();
      if (mounted) setState(() { _cameras = cams; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _showRenameDialog(Map<String, dynamic> cam) async {
    final TextEditingController ctrl = TextEditingController(text: cam['name'] as String);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('cameraName')),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: InputDecoration(hintText: tr('cameraName'))),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ok'))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await Api.I.renameCamera(cam['id'] as String, ctrl.text.trim());
      await _load();
    }
  }

  Future<void> _showAddDialog() async {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController urlCtrl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('addCamera')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(controller: nameCtrl, autofocus: true,
                decoration: InputDecoration(labelText: tr('cameraName'))),
            const SizedBox(height: 8),
            TextField(controller: urlCtrl,
                decoration: InputDecoration(labelText: tr('cameraUrl')),
                keyboardType: TextInputType.url),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ok'))),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty && urlCtrl.text.trim().isNotEmpty) {
      await Api.I.addCamera(nameCtrl.text.trim(), urlCtrl.text.trim());
      await _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> cam) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('cameraDelete')),
        content: Text(tr('cameraDeleteConfirm')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('cameraDelete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Api.I.deleteCamera(cam['id'] as String);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: <Widget>[
          const Icon(Icons.videocam_outlined, size: 20),
          const SizedBox(width: 8),
          Text(tr('cameras')),
        ]),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _cameras.isEmpty
                  ? Center(child: Text(tr('noCameras'),
                        style: const TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _cameras.length,
                      itemBuilder: (BuildContext ctx, int i) {
                        final Map<String, dynamic> cam = _cameras[i];
                        return ListTile(
                          leading: const Icon(Icons.videocam_outlined),
                          title: Text(cam['name'] as String),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _showRenameDialog(cam),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20,
                                    color: Colors.redAccent),
                                onPressed: () => _confirmDelete(cam),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CameraFeedScreen(
                                id: cam['id'] as String,
                                name: cam['name'] as String,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera feed screen
// ─────────────────────────────────────────────────────────────────────────────

class CameraFeedScreen extends StatefulWidget {
  const CameraFeedScreen({super.key, required this.id, required this.name});
  final String id;
  final String name;
  @override
  State<CameraFeedScreen> createState() => _CameraFeedScreenState();
}

class _CameraFeedScreenState extends State<CameraFeedScreen> with LangAware {
  Uint8List? _frame;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final Uint8List bytes = await Api.I.cameraSnapshot(widget.id);
      if (mounted) setState(() { _frame = bytes; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = _frame == null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: <Widget>[
          const Icon(Icons.videocam_outlined, size: 20),
          const SizedBox(width: 8),
          Text(widget.name),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _frame == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.videocam_off_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(_error ?? '', style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : Stack(
                  children: <Widget>[
                    InteractiveViewer(
                      child: Center(child: Image.memory(_frame!, gaplessPlayback: true,
                          fit: BoxFit.contain)),
                    ),
                    if (_error != null)
                      Positioned(
                        bottom: 12, left: 12, right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.orangeAccent),
                              textAlign: TextAlign.center),
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tapo smart socket list screen
// ─────────────────────────────────────────────────────────────────────────────

class TapoDevicesScreen extends StatefulWidget {
  const TapoDevicesScreen({super.key});
  @override
  State<TapoDevicesScreen> createState() => _TapoDevicesScreenState();
}

class _TapoDevicesScreenState extends State<TapoDevicesScreen> with LangAware {
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  final Set<String> _toggling = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final List<Map<String, dynamic>> devs = await Api.I.listTapoDevices();
      if (mounted) setState(() { _devices = devs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(Map<String, dynamic> device, {required bool on}) async {
    final String id = device['id'] as String;
    setState(() => _toggling.add(id));
    try {
      if (on) {
        await Api.I.tapoOn(id);
      } else {
        await Api.I.tapoOff(id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _toggling.remove(id));
    }
  }

  Future<void> _showAddDialog() async {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController ipCtrl = TextEditingController();
    bool adding = false;
    String? addError;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter ss) => AlertDialog(
          title: Text(tr('tapoAdd')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('tapoSocketName')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ipCtrl,
                decoration: InputDecoration(labelText: tr('tapoIpAddress')),
                keyboardType: TextInputType.phone,
              ),
              if (addError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(addError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
            FilledButton(
              onPressed: adding
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty || ipCtrl.text.trim().isEmpty) return;
                      ss(() { adding = true; addError = null; });
                      try {
                        await Api.I.tapoAddDevice(
                            ipCtrl.text.trim(), nameCtrl.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                      } catch (e) {
                        ss(() { addError = e.toString(); adding = false; });
                      }
                    },
              child: adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('ok')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(Map<String, dynamic> device) async {
    final TextEditingController ctrl =
        TextEditingController(text: device['name'] as String);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('tapoRename')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ok'))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await Api.I.tapoRenameDevice(device['id'] as String, ctrl.text.trim());
      await _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> device) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('tapoDelete')),
        content: Text(tr('tapoDeleteConfirm')),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('tapoDelete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Api.I.tapoDeleteDevice(device['id'] as String);
      await _load();
    }
  }

  Future<void> _showContextMenu(Map<String, dynamic> device) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('tapoRename')),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(tr('tapoDelete'),
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      await _showRenameDialog(device);
    } else if (action == 'delete') {
      await _confirmDelete(device);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: <Widget>[
          const Icon(Icons.power_outlined, size: 20),
          const SizedBox(width: 8),
          Text(tr('tapoDevices')),
        ]),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)))
              : _devices.isEmpty
                  ? Center(
                      child: Text(tr('tapoNoDevices'),
                          style: const TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (BuildContext ctx, int i) {
                        final Map<String, dynamic> dev = _devices[i];
                        final bool on = dev['on'] as bool? ?? false;
                        final bool online = dev['online'] as bool? ?? false;
                        final bool busy =
                            _toggling.contains(dev['id'] as String);
                        final int sig = dev['signal_level'] as int? ?? 0;
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: on
                                  ? Colors.green.withAlpha(38)
                                  : Colors.grey.withAlpha(25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.power_outlined,
                                color: on ? Colors.green : Colors.grey),
                          ),
                          title: Text(dev['name'] as String),
                          subtitle: online
                              ? Text(
                                  on ? tr('tapoOn') : tr('tapoOff'),
                                  style: TextStyle(
                                      color: on ? Colors.green : Colors.grey,
                                      fontSize: 12),
                                )
                              : Text(tr('tapoOffline'),
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (online) _TapoSignalIcon(level: sig),
                              const SizedBox(width: 4),
                              if (busy)
                                const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                              else
                                Switch(
                                  value: on,
                                  onChanged: online
                                      ? (bool v) => _toggle(dev, on: v)
                                      : null,
                                ),
                            ],
                          ),
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(
                                builder: (_) => TapoDeviceDetailScreen(
                                  id: dev['id'] as String,
                                  name: dev['name'] as String,
                                ),
                              ))
                              .then((_) => _load()),
                          onLongPress: () => _showContextMenu(dev),
                        );
                      },
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tapo device detail screen
// ─────────────────────────────────────────────────────────────────────────────

class TapoDeviceDetailScreen extends StatefulWidget {
  const TapoDeviceDetailScreen(
      {super.key, required this.id, required this.name});
  final String id;
  final String name;
  @override
  State<TapoDeviceDetailScreen> createState() =>
      _TapoDeviceDetailScreenState();
}

class _TapoDeviceDetailScreenState extends State<TapoDeviceDetailScreen>
    with LangAware {
  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _schedule = <Map<String, dynamic>>[];
  Map<String, dynamic>? _activeTimer;
  bool _loading = true;
  bool _cloudLoading = true;
  String? _error;
  bool _powerBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_info == null) setState(() { _loading = true; _error = null; });
    try {
      final Map<String, dynamic> info = await Api.I.tapoInfo(widget.id);
      if (!mounted) return;
      setState(() { _info = info; _loading = false; _error = null; });
      // Load cloud data (timer/schedule) in background — don't block the page
      _loadCloudData();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadCloudData() async {
    if (mounted) setState(() => _cloudLoading = true);
    try {
      final List<Map<String, dynamic>> results = await Future.wait(<Future<Map<String, dynamic>>>[
        Api.I.tapoGetSchedule(widget.id),
        Api.I.tapoGetTimer(widget.id),
      ]);
      if (!mounted) return;
      final List<dynamic> schedRules =
          (results[0]['rules'] as List<dynamic>?) ?? <dynamic>[];
      final List<dynamic> timerRules =
          (results[1]['rules'] as List<dynamic>?) ?? <dynamic>[];
      setState(() {
        _schedule = schedRules.cast<Map<String, dynamic>>();
        _activeTimer = timerRules.isNotEmpty
            ? timerRules.first as Map<String, dynamic>?
            : null;
        _cloudLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  Future<void> _togglePower() async {
    if (_info == null || _powerBusy) return;
    final bool isOn = _info!['on'] as bool? ?? false;
    setState(() => _powerBusy = true);
    try {
      if (isOn) {
        await Api.I.tapoOff(widget.id);
      } else {
        await Api.I.tapoOn(widget.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _powerBusy = false);
    }
  }

  Future<void> _toggleLed({required bool on}) async {
    try {
      await Api.I.tapoSetLed(widget.id, on: on);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showTimerDialog() async {
    final TextEditingController minsCtrl =
        TextEditingController(text: '60');
    bool turnOn = false;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter ss) => AlertDialog(
          title: Text(tr('tapoSetTimer')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: minsCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: tr('tapoTimerMinutes'), suffixText: 'min'),
              ),
              const SizedBox(height: 16),
              Row(children: <Widget>[
                Text(tr('tapoTimerAction')),
                const Spacer(),
                ToggleButtons(
                  isSelected: <bool>[turnOn, !turnOn],
                  onPressed: (int i) => ss(() => turnOn = i == 0),
                  children: <Widget>[
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(tr('tapoOn'))),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(tr('tapoOff'))),
                  ],
                ),
              ]),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('cancel'))),
            FilledButton(
              onPressed: () async {
                final int? mins = int.tryParse(minsCtrl.text.trim());
                if (mins == null || mins < 1 || mins > 1440) return;
                Navigator.pop(ctx);
                try {
                  await Api.I.tapoSetTimer(widget.id,
                      minutes: mins, turnOn: turnOn);
                  await _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: Text(tr('ok')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelTimer() async {
    try {
      await Api.I.tapoCancelTimer(widget.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showAddScheduleDialog() async {
    final List<bool> days = List<bool>.filled(7, false);
    bool turnOn = true;
    bool saving = false;
    TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);
    const List<String> dayLabels = <String>[
      'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'
    ];
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter ss) => AlertDialog(
          title: Text(tr('tapoAddSchedule')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(tr('tapoDays'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: List<Widget>.generate(
                  7,
                  (int i) => FilterChip(
                    label: Text(dayLabels[i]),
                    selected: days[i],
                    onSelected: saving ? null : (bool v) => ss(() => days[i] = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Text(tr('tapoTime')),
                const Spacer(),
                TextButton(
                  onPressed: saving ? null : () async {
                    final TimeOfDay? picked =
                        await showTimePicker(context: context, initialTime: time);
                    if (picked != null) ss(() => time = picked);
                  },
                  child: Text(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: <Widget>[
                Text(tr('tapoAction')),
                const Spacer(),
                ToggleButtons(
                  isSelected: <bool>[turnOn, !turnOn],
                  onPressed: saving ? null : (int i) => ss(() => turnOn = i == 0),
                  children: <Widget>[
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(tr('tapoOn'))),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(tr('tapoOff'))),
                  ],
                ),
              ]),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: Text(tr('cancel'))),
            FilledButton(
              onPressed: saving || !days.any((bool d) => d) ? null : () async {
                ss(() => saving = true);
                try {
                  await Api.I.tapoAddSchedule(
                    widget.id,
                    wday: List<int>.generate(7, (int i) => days[i] ? 1 : 0),
                    hour: time.hour,
                    minute: time.minute,
                    turnOn: turnOn,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('ok')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSchedule(String ruleId) async {
    try {
      await Api.I.tapoDeleteSchedule(widget.id, ruleId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  String _scheduleLabel(Map<String, dynamic> rule) {
    final int weekDay = rule['week_day'] as int? ?? 0;
    final int smin = rule['s_min'] as int? ?? 0;
    final bool turnOn =
        ((rule['desired_states'] as Map<String, dynamic>?)?['on'] as bool?) ??
            true;
    final int h = smin ~/ 60;
    final int m = smin % 60;
    final String time =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    const List<String> labels = <String>['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    final List<String> active = <String>[
      for (int i = 0; i < 7; i++)
        if (weekDay & (1 << i) != 0) labels[i]
    ];
    final String daysStr = active.isEmpty ? '' : '  ·  ${active.join(' ')}';
    return '$time$daysStr  ·  ${turnOn ? tr('tapoOn') : tr('tapoOff')}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _info == null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)))
              : _buildBody(colors),
    );
  }

  Widget _buildBody(ColorScheme colors) {
    final Map<String, dynamic> info = _info!;
    final bool on = info['on'] as bool? ?? false;
    final bool ledOff = info['led_off'] as bool? ?? false;
    final int onTime = info['on_time'] as int? ?? 0;
    final int sig = info['signal_level'] as int? ?? 0;
    final Map<String, dynamic> usage =
        (info['usage'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          // ── Power ──────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(children: <Widget>[
                GestureDetector(
                  onTap: _powerBusy ? null : _togglePower,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on
                          ? Colors.green.withAlpha(38)
                          : colors.surfaceContainerHighest,
                      border: Border.all(
                          color: on ? Colors.green : Colors.grey, width: 2.5),
                    ),
                    child: _powerBusy
                        ? const Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(Icons.power_settings_new,
                            size: 52,
                            color: on ? Colors.green : Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  on ? tr('tapoOn') : tr('tapoOff'),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.green : Colors.grey),
                ),
                if (on && onTime > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${tr('tapoUptime')}: ${_formatDuration(onTime)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),

          // ── Device info ────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(tr('tapoDeviceInfo'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 10),
                  _TapoInfoRow(label: tr('tapoModel'),
                      value: info['model'] as String? ?? '—'),
                  _TapoInfoRow(label: tr('tapoFirmware'),
                      value: info['fw_ver'] as String? ?? '—'),
                  _TapoInfoRow(label: tr('tapoHardware'),
                      value: info['hw_ver'] as String? ?? '—'),
                  _TapoInfoRow(label: 'MAC',
                      value: info['mac'] as String? ?? '—'),
                  _TapoInfoRow(label: 'IP',
                      value: info['ip'] as String? ?? '—'),
                  _TapoInfoRow(
                      label: tr('tapoSignal'),
                      value: '${info['rssi'] ?? 0} dBm ($sig/3)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── LED ────────────────────────────────────────
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.lightbulb_outline),
              title: Text(tr('tapoLed')),
              subtitle: Text(ledOff ? tr('tapoOff') : tr('tapoOn')),
              value: !ledOff,
              onChanged: (bool v) => _toggleLed(on: v),
            ),
          ),
          const SizedBox(height: 10),

          // ── Usage ──────────────────────────────────────
          if (usage.isNotEmpty) ...<Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(tr('tapoUsage'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(children: <Widget>[
                      Expanded(child: _TapoUsageStat(
                          label: tr('tapoToday'),
                          minutes: usage['today'] as int? ?? 0)),
                      Expanded(child: _TapoUsageStat(
                          label: tr('tapoPast7'),
                          minutes: usage['past7'] as int? ?? 0)),
                      Expanded(child: _TapoUsageStat(
                          label: tr('tapoPast30'),
                          minutes: usage['past30'] as int? ?? 0)),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Timer ──────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(tr('tapoTimer'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    if (_activeTimer != null)
                      TextButton(
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent),
                        onPressed: _cancelTimer,
                        child: Text(tr('tApoCancelTimer')),
                      )
                    else
                      TextButton(
                          onPressed: _showTimerDialog,
                          child: Text(tr('tapoSetTimer'))),
                  ]),
                  if (_activeTimer != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Builder(builder: (BuildContext context) {
                      final int remain =
                          _activeTimer!['remain'] as int? ?? 0;
                      final bool timerOn =
                          ((_activeTimer!['desired_states']
                                      as Map<String, dynamic>?)?['on']
                                  as bool?) ??
                              false;
                      return Text(
                        '${_formatDuration(remain)} → ${timerOn ? tr('tapoOn') : tr('tapoOff')}',
                        style: const TextStyle(fontSize: 13),
                      );
                    }),
                  ] else
                    Text(tr('tapoNoTimer'),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Schedule ───────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    const Icon(Icons.schedule_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(tr('tapoSchedule'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    TextButton(
                        onPressed: _showAddScheduleDialog,
                        child: Text(tr('tapoAddSchedule'))),
                  ]),
                  if (_cloudLoading && _schedule.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    )
                  else if (_schedule.isEmpty)
                    Text(tr('tapoNoSchedule'),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13))
                  else
                    ..._schedule.map((Map<String, dynamic> rule) {
                      final bool enabled =
                          rule['enable'] as bool? ?? true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(Icons.access_time_outlined,
                            size: 18,
                            color: enabled ? null : Colors.grey),
                        title: Text(
                          _scheduleLabel(rule),
                          style: TextStyle(
                              fontSize: 13,
                              color: enabled ? null : Colors.grey),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: Colors.redAccent),
                          onPressed: () => _deleteSchedule(
                              rule['id'] as String? ?? ''),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tapo helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TapoSignalIcon extends StatelessWidget {
  const _TapoSignalIcon({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final Color color = level >= 3
        ? Colors.green
        : level >= 2
            ? Colors.orange
            : Colors.redAccent;
    final IconData icon = level >= 3
        ? Icons.signal_wifi_4_bar
        : level >= 2
            ? Icons.network_wifi_2_bar
            : level >= 1
                ? Icons.network_wifi_1_bar
                : Icons.signal_wifi_0_bar;
    return Icon(icon, size: 16, color: color);
  }
}

class _TapoInfoRow extends StatelessWidget {
  const _TapoInfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: <Widget>[
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

class _TapoUsageStat extends StatelessWidget {
  const _TapoUsageStat({required this.label, required this.minutes});
  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    final String display =
        h > 0 ? '${h}h${m > 0 ? ' ${m}m' : ''}' : '${m}m';
    return Column(children: <Widget>[
      Text(display,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}
