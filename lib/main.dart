import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'i18n.dart';

final ValueNotifier<int> authTick = ValueNotifier<int>(0);
final ValueNotifier<int> selectedTab = ValueNotifier<int>(0); // 0=Search 1=Downloads 2=Library

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
  runApp(const NasApp());
}

class NasApp extends StatelessWidget {
  const NasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const AuthGate(),
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: authTick,
      builder: (BuildContext context, int _, Widget? _) {
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

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.setBaseUrl(_url.text);
      await Api.I.login(_user.text.trim(), _pass.text);
      authTick.value++;
    } catch (_) {
      setState(() => _error = tr('loginFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
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
              const SizedBox(height: 20),
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: selectedTab,
      builder: (BuildContext context, int tab, Widget? _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('app')),
          actions: <Widget>[
            const LangButton(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String v) async {
                if (v == 'sessions') {
                  Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SessionsScreen()));
                } else if (v == 'logout') {
                  await Api.I.logout();
                  authTick.value++;
                }
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                if (Api.I.isAdmin)
                  PopupMenuItem<String>(
                    value: 'sessions',
                    child: Row(children: <Widget>[
                      const Icon(Icons.cast_connected, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('plexSessions')),
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
              ],
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

// ----------------------------- search ---------------------------------------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with LangAware {
  final TextEditingController _q = TextEditingController();
  String _type = 'movie';
  List<dynamic> _results = <dynamic>[];
  bool _busy = false;
  bool _searched = false; // a search has actually run
  String? _grabbing; // key of the item currently being requested

  String _key(Map<String, dynamic> m) => '$_type-${m['tmdbId'] ?? m['tvdbId']}';

  Future<void> _run() async {
    if (_q.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _searched = true;
    });
    try {
      final List<dynamic> r = await Api.I.search(_q.text.trim(), _type);
      setState(() => _results = r);
    } catch (_) {
      setState(() => _results = <dynamic>[]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _emptyState() {
    return Center(
      child: _searched
          ? Text(tr('noResults'))
          : Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.movie_filter_outlined,
                      size: 64, color: Colors.white.withValues(alpha: 0.4)),
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
    try {
      await Api.I.grab(
        type: _type,
        tmdbId: _type == 'movie' ? item['tmdbId'] as int? : null,
        tvdbId: _type == 'tv' ? item['tvdbId'] as int? : null,
        tier: tier,
      );
      // TV grabs are async (Sonarr searches + queues episodes over time) -> say so.
      _snackGo(_type == 'tv' ? tr('requestedTv') : tr('added'));
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
          child: Row(
            children: <Widget>[
              Expanded(
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
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'movie', label: Text(tr('movie'))),
                  ButtonSegment<String>(value: 'tv', label: Text(tr('tv'))),
                ],
                selected: <String>{_type},
                onSelectionChanged: (Set<String> s) {
                  setState(() => _type = s.first);
                  _run(); // re-search for the newly selected type (no-op if query empty)
                },
              ),
            ],
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
                      subtitle: Text(m['year']?.toString() ?? ''),
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
        // First time data arrives: open Active unless nothing is in progress.
        if (!_didInitTab && d.isNotEmpty) {
          _didInitTab = true;
          final bool hasActive = d.any((dynamic e) =>
              _group((e as Map<String, dynamic>)['state']?.toString() ?? '') <= 1);
          _tabs!.index = hasActive ? 0 : 1;
        }
      });
    } catch (_) {}
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
        });
      }
    } catch (_) {}
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
              Text('${pct.toStringAsFixed(0)}% of storage used',
                  style: const TextStyle(fontSize: 12)),
              Text('${_freeStr(free)} free', style: const TextStyle(fontSize: 12)),
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
                              transcode ? 'transcode' : 'direct',
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
