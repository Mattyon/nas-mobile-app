import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'detail.dart';
import 'i18n.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Api.I.init();
  if (Platform.isAndroid) await _initNotifications();
  final prefs = await SharedPreferences.getInstance();
  final bool isDark = prefs.getBool('darkMode') ?? true;
  themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  runApp(const NasApp());
}

Future<void> _toggleTheme() async {
  final isDark = themeMode.value == ThemeMode.dark;
  themeMode.value = isDark ? ThemeMode.light : ThemeMode.dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('darkMode', !isDark);
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
        onPressed: toggleLang,
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
class PosterImage extends StatelessWidget {
  final String? url;
  const PosterImage(this.url, {super.key});
  static const double _w = 46, _h = 69;

  Widget _fallback(IconData icon) =>
      Container(width: _w, height: _h, color: Colors.black26, child: Icon(icon, size: 20));

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _fallback(Icons.movie_outlined);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url!,
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(Icons.broken_image_outlined),
        loadingBuilder: (BuildContext c, Widget child, ImageChunkEvent? p) =>
            p == null ? child : _fallback(Icons.image_outlined),
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
                  } else if (v == 'speedtest') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const SpeedtestScreen()));
                  } else if (v == 'ai') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const AiChatsListScreen()));
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
                  if (Api.I.isSuperadmin)
                    PopupMenuItem<String>(
                      value: 'ai',
                      child: Row(children: <Widget>[
                        const Icon(Icons.smart_toy_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('aiChats')),
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
                  PopupMenuItem<String>(
                    value: 'neweps',
                    child: Row(children: <Widget>[
                      const Icon(Icons.tv, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('checkNewEps')),
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
    // Step 1: language picker
    final String? language = await _pickLanguage(item);
    if (language == null || !mounted) return;
    // Step 2: quality picker
    final String? tier = await _pickQuality(language);
    if (tier == null || !mounted) return;
    await _doGrab(item, language, tier);
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

  Future<void> _doGrab(Map<String, dynamic> item, String language, String tier) async {
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
      );

      if (result['no_czech_audio'] == true) {
        closeStages();
        if (mounted) setState(() => _grabbing = null);
        await _offerEnglishFallback(item, tier, result['title']?.toString() ?? '');
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
      Map<String, dynamic> item, String tier, String title) async {
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
      await _doGrab(item, 'en', tier);
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
                      leading: PosterImage(m['poster'] as String?),
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
    final int h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  static const Set<String> _activeStates = <String>{
    'downloading', 'forcedDL', 'metaDL', 'stalledDL', 'checkingDL', 'allocating'
  };
  static const Set<String> _failedStates = <String>{'error', 'missingFiles'};

  static const Map<String, String> _stateLabel = <String, String>{
    'downloading': 'Downloading',
    'forcedDL': 'Downloading',
    'stalledDL': 'Stalled — no peers',
    'metaDL': 'Fetching metadata',
    'checkingDL': 'Checking',
    'allocating': 'Allocating',
    'queuedDL': 'Queued',
    'pausedDL': 'Paused',
    'stoppedDL': 'Stopped',
    'uploading': 'Seeding',
    'forcedUP': 'Seeding',
    'stalledUP': 'Seeding (stalled)',
    'checkingUP': 'Checking',
    'pausedUP': 'Paused',
    'stoppedUP': 'Stopped',
    'error': 'Error',
    'missingFiles': 'Missing files',
    'moving': 'Moving',
    'unknown': 'Unknown',
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
          Text('${pct.toStringAsFixed(1)}%  •  ${t['dlspeed_mbs'] ?? 0} MB/s  •  '
              'ETA ${_eta(t['eta_sec'])}  •  '
              '${_stateLabel[t['state']?.toString()] ?? t['state'] ?? ''}', style: red),
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

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
    try {
      await Api.I.deleteItem(_type, m['id'] as int);
      await _refresh();
    } catch (_) {}
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (BuildContext context, int i) {
                final Map<String, dynamic> m = _items[i] as Map<String, dynamic>;
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
                  leading: PosterImage(m['poster'] as String?),
                  title: Text(m['title']?.toString() ?? ''),
                  subtitle: Row(
                    children: <Widget>[
                      Icon(hasFile ? Icons.check_circle : Icons.hourglass_empty,
                          size: 14, color: hasFile ? Colors.green : Colors.grey),
                      const SizedBox(width: 4),
                      Text(yearSize),
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
              onPressed: saving ? null : () => Navigator.of(ctx2).pop(false),
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
                          );
                        } else {
                          await Api.I.createUser(
                            username: nameCtrl.text.trim(),
                            password: passCtrl.text,
                            displayname: dispCtrl.text.trim(),
                            isAdmin: isAdmin,
                            isAiAccess: isAiAccess,
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
      } catch (_) {}
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
      body: _loading
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
      if (mounted) setState(() { _report = r; });
    } catch (_) {}
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
      body: _running
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(tr('healthCheckRunning')),
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

    if (_report == null || _report!.isEmpty) {
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
    final String? lastRun = _report!['last_run'] as String?;
    final num? durationSec = _report!['duration_sec'] as num?;

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
      final String msg = result['message'] as String? ?? (ok ? 'Done.' : 'Could not resolve.');
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(tr(ok ? 'aiFixResult' : 'aiFixFailed')),
          content: Text(msg),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('ok')),
            ),
          ],
        ),
      );
      if (ok && mounted) _run(); // re-run health check so the fixed warning disappears
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
    final bool canFix = category != 'check_error';
    final bool isResolving = _resolving == message;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(isWarning ? Icons.warning_amber : Icons.error_outline, color: color),
        title: Text(_categoryLabel(category),
            style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: message.isNotEmpty
            ? Text(message, style: const TextStyle(fontSize: 12))
            : null,
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
    final String? itemType = item['item_type'] as String?;
    final int? itemId = item['item_id'] as int?;
    final String swapKey = '${itemType}_${itemId}_$queueItemId';
    final bool swapping = _swapping == swapKey;

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
                      label: Text(tr('aiFix')),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'missing_file':    return tr('healthCheckMissing');
      case 'suspicious_size':
      case 'small_file':      return tr('healthCheckSmall');
      case 'not_imported':    return tr('healthCheckNotImported');
      case 'torrent_error':   return tr('healthCheckQbtError');
      case 'stalled':         return tr('healthCheckStalled');
      case 'sonarr':          return tr('healthCheckSonarr');
      case 'radarr':          return tr('healthCheckRadarr');
      default:                return category;
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
