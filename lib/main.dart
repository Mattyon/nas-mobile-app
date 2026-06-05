import 'package:flutter/material.dart';
import 'api.dart';
import 'i18n.dart';

final ValueNotifier<int> authTick = ValueNotifier<int>(0);

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
      builder: (BuildContext context, String _, Widget? _) => TextButton(
        onPressed: toggleLang,
        child: Text(tr('language'), style: const TextStyle(color: Colors.white)),
      ),
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
  int _tab = 0;
  static const List<Widget> _pages = <Widget>[
    SearchScreen(),
    DownloadsScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('app')),
        actions: <Widget>[
          const LangButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: tr('logout'),
            onPressed: () async {
              await Api.I.logout();
              authTick.value++;
            },
          ),
        ],
      ),
      body: _pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: <NavigationDestination>[
          NavigationDestination(icon: const Icon(Icons.search), label: tr('search')),
          NavigationDestination(icon: const Icon(Icons.download), label: tr('downloads')),
          NavigationDestination(icon: const Icon(Icons.video_library), label: tr('library')),
        ],
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
  String? _grabbing; // key of the item currently being requested

  String _key(Map<String, dynamic> m) => '$_type-${m['tmdbId'] ?? m['tvdbId']}';

  Future<void> _run() async {
    if (_q.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final List<dynamic> r = await Api.I.search(_q.text.trim(), _type);
      setState(() => _results = r);
    } catch (_) {
      setState(() => _results = <dynamic>[]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    setState(() => _grabbing = _key(item));   // disable + spinner on this item
    try {
      await Api.I.grab(
        type: _type,
        tmdbId: _type == 'movie' ? item['tmdbId'] as int? : null,
        tvdbId: _type == 'tv' ? item['tvdbId'] as int? : null,
        tier: tier,
      );
      _snack(tr('added'));
    } catch (_) {
      _snack(tr('error'));
    } finally {
      if (mounted) setState(() => _grabbing = null);   // re-enable
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
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
              ? Center(child: Text(tr('noResults')))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Map<String, dynamic> m = _results[i] as Map<String, dynamic>;
                    final bool busy = _grabbing == _key(m);
                    return ListTile(
                      leading: PosterImage(m['poster'] as String?),
                      title: Text(m['title']?.toString() ?? ''),
                      subtitle: Text(m['year']?.toString() ?? ''),
                      trailing: FilledButton.tonal(
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

class _DownloadsScreenState extends State<DownloadsScreen> with LangAware {
  List<dynamic> _items = <dynamic>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> d = await Api.I.downloads();
      if (mounted) setState(() => _items = d);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _items.isEmpty
          ? ListView(children: <Widget>[
              const SizedBox(height: 120),
              Center(child: Text(tr('noResults'))),
            ])
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (BuildContext context, int i) {
                final Map<String, dynamic> t = _items[i] as Map<String, dynamic>;
                final double pct = (t['progress'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  title: Text(t['name']?.toString() ?? '', maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: pct / 100),
                      const SizedBox(height: 4),
                      Text('${pct.toStringAsFixed(1)}%  •  '
                          '${t['dlspeed_mbps'] ?? 0} Mbit/s  •  ${t['state'] ?? ''}'),
                    ],
                  ),
                );
              },
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> r = await Api.I.library(_type, _q.text.trim());
      if (mounted) setState(() => _items = r);
    } catch (_) {}
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
                return ListTile(
                  leading: PosterImage(m['poster'] as String?),
                  title: Text(m['title']?.toString() ?? ''),
                  subtitle: Row(
                    children: <Widget>[
                      Icon(hasFile ? Icons.check_circle : Icons.hourglass_empty,
                          size: 14, color: hasFile ? Colors.green : Colors.grey),
                      const SizedBox(width: 4),
                      Text(m['year']?.toString() ?? ''),
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
      ],
    );
  }
}
