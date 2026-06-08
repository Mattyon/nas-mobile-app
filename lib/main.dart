import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'i18n.dart';

final ValueNotifier<int> authTick = ValueNotifier<int>(0);
final ValueNotifier<int> selectedTab = ValueNotifier<int>(0); // 0=Search 1=Downloads 2=Library
final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
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

/// Rebuilds a screen's State when the language changes — WITHOUT remounting, so
/// screen state (search results, current tab, text fields) is preserved.
mixin LangAware<T extends StatefulWidget> on State<T> {
  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    lang.addListener(_onLangChanged);
  }

  @override
  void dispose() {
    lang.removeListener(_onLangChanged);
    super.dispose();
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

/// Official cover art loaded from the TMDb/TVDB URL the gateway provides.
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
      appBar: AppBar(title: Text(tr('app')), actions: const <Widget>[LangButton()]),
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
            const LangButton(),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeMode,
              builder: (BuildContext ctx2, ThemeMode mode, Widget? _) =>
                  PopupMenuButton<String>(
                icon: const Icon(Icons.menu),
                onSelected: (String v) async {
                  if (v == 'sessions') {
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
                        Text(tr('plexSessions')),
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
    if (_busy) return const SizedBox.shrink(); // loading bar at top shows progress
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
    final String? tier = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('pickQuality'),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final String t in <String>['fast', 'balanced', 'best'])
              ListTile(
                leading: const Icon(Icons.download),
                title: Text(tr(t)),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (tier == null) return;
    setState(() => _grabbing = _key(item));
    final VoidCallback closeStages = _showStages();
    final String itype = item['type']?.toString() ?? 'movie';
    try {
      await Api.I.grab(
        type: itype,
        tmdbId: itype == 'movie' ? item['tmdbId'] as int? : null,
        tvdbId: itype == 'tv' ? item['tvdbId'] as int? : null,
        tier: tier,
      );
      // TV grabs are async (Sonarr searches + queues episodes over time) -> say so.
      _snackGo(itype == 'tv' ? tr('requestedTv') : tr('added'));
    } catch (_) {
      _snack(tr('error'));
    } finally {
      closeStages();
      if (mounted) setState(() => _grabbing = null);
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
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _results.isEmpty
              ? _emptyState()
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Map<String, dynamic> m = _results[i] as Map<String, dynamic>;
                    final bool busy = _grabbing == _key(m);
                    final bool onDisk = m['hasFile'] == true;
                    return ListTile(
                      leading: PosterImage(m['poster'] as String?),
                      title: Text(m['title']?.toString() ?? ''),
                      subtitle: Row(
                        children: <Widget>[
                          _typeBadge(m['type']?.toString()),
                          const SizedBox(width: 6),
                          Text(m['year']?.toString() ?? ''),
                        ],
                      ),
                      // On disk → green check, no button.
                      // Added but no file → show download button (allows retry).
                      // Not added → download button.
                      trailing: onDisk
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.check_circle, size: 18, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(tr('onDisk'), style: const TextStyle(fontSize: 12)),
                              ],
                            )
                          : FilledButton.tonal(
                              onPressed: busy ? null : () => _grab(m),
                              child: busy
                                  ? const SizedBox(
                                      height: 18, width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(tr('download')),
                            ),
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

  bool _isFailed(String s) => _failedStates.contains(s);

  int _group(String s) {
    if (_activeStates.contains(s)) return 0; // active downloads
    if (s == 'queuedDL') return 1;           // queued
    if (_isFailed(s)) return 3;              // failed (last, red)
    return 2;                                // finished / seeding / paused / stopped
  }

  // active=true → downloading+queued; active=false → finished+failed. Filtered by search.
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
        return ((b['progress'] as num?)?.toDouble() ?? 0)
            .compareTo((a['progress'] as num?)?.toDouble() ?? 0);
      }
      return 0;
    });
    return items;
  }

  Widget _tile(Map<String, dynamic> t) {
    final double pct = (t['progress'] as num?)?.toDouble() ?? 0;
    final bool failed = _isFailed(t['state']?.toString() ?? '');
    final TextStyle? red = failed ? const TextStyle(color: Colors.redAccent) : null;
    return ListTile(
      title: Text(t['name']?.toString() ?? '',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: red),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 4),
          LinearProgressIndicator(value: pct / 100, color: failed ? Colors.redAccent : null),
          const SizedBox(height: 4),
          Text('${pct.toStringAsFixed(1)}%  •  ${t['dlspeed_mbps'] ?? 0} Mbit/s  •  '
              'ETA ${_eta(t['eta_sec'])}  •  ${t['state'] ?? ''}', style: red),
        ],
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return ListView(children: <Widget>[
        const SizedBox(height: 120),
        Center(child: Text(tr('noResults'))),
      ]);
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (BuildContext context, int i) => _tile(items[i]),
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
                isDense: true, hintText: tr('search'), prefixIcon: const Icon(Icons.search)),
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
              RefreshIndicator(onRefresh: _refresh, child: _list(active)),
              RefreshIndicator(onRefresh: _refresh, child: _list(finished)),
            ],
          ),
        ),
        _speedBar(),
      ],
    );
  }

  Widget _speedBar() {
    final num dl = (_xfer['dl_mbps'] as num?) ?? 0;
    final num up = (_xfer['up_mbps'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.south, size: 16, color: Colors.lightBlueAccent),
            const SizedBox(width: 4),
            Text('$dl Mbit/s'),
          ]),
          Row(children: <Widget>[
            const Icon(Icons.north, size: 16, color: Colors.greenAccent),
            const SizedBox(width: 4),
            Text('$up Mbit/s'),
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
                      hintText: tr('search'), prefixIcon: const Icon(Icons.search)),
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
      final List<dynamic> s = await Api.I.plexSessions();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('plexSessions'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(child: Text(tr('noSessions')))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Map<String, dynamic> s = _sessions[i] as Map<String, dynamic>;
                      final double pct = (s['progress_pct'] as num?)?.toDouble() ?? 0;
                      final bool playing = s['state'] == 'playing';
                      final num? bw = s['bandwidth_kbps'] as num?;
                      final String loc = (s['location'] ?? '').toString().toUpperCase();
                      final bool transcode = s['transcode'] == true;
                      return ListTile(
                        leading: Icon(playing ? Icons.play_circle : Icons.pause_circle,
                            color: playing ? Colors.green : Colors.orangeAccent),
                        title: Text('${s['user'] ?? '?'} — ${s['title'] ?? ''}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: pct / 100),
                            const SizedBox(height: 4),
                            Text(<String>[
                              '${pct.toStringAsFixed(0)}%',
                              if (s['player'] != null) s['player'].toString(),
                              if (s['address'] != null) '${s['address']}${loc.isNotEmpty ? ' ($loc)' : ''}',
                              if (bw != null) '${(bw / 1000).toStringAsFixed(1)} Mbit/s',
                              transcode ? tr('transcode') : tr('direct'),
                            ].join('  •  ')),
                          ],
                        ),
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
                          );
                        } else {
                          await Api.I.createUser(
                            username: nameCtrl.text.trim(),
                            password: passCtrl.text,
                            displayname: dispCtrl.text.trim(),
                            isAdmin: isAdmin,
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
