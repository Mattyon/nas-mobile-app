import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'api.dart';
import 'i18n.dart';

const String _kImg = 'https://image.tmdb.org/t/p/';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> with LangAware {
  Map<String, dynamic>? _detail;
  Map<String, dynamic>? _tmdb;
  bool _loading = true;
  bool _overviewExpanded = false;
  final Set<int> _expandedSeasons = <int>{};
  bool _grabbing = false;

  Map<String, dynamic> get _item => widget.item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool isMovie = _item['type'] == 'movie';
    final int tmdbId = (_item['tmdbId'] as int?) ?? 0;
    final int tvdbId = (_item['tvdbId'] as int?) ?? 0;
    final String langCode = lang.value == 'cs' ? 'cs-CZ' : 'en-US';
    setState(() => _loading = true);
    try {
      final List<Object?> r = await Future.wait<Object?>(<Future<Object?>>[
        Api.I.itemDetail(
          type: _item['type'] as String? ?? 'movie',
          tmdbId: tmdbId,
          tvdbId: tvdbId,
        ),
        if (tmdbId > 0)
          isMovie
              ? Api.I.tmdbMovieDetails(tmdbId, language: langCode)
              : Api.I.tmdbTvDetails(tmdbId, language: langCode)
        else
          Future<Map<String, dynamic>>.value(<String, dynamic>{}),
      ]);
      if (!mounted) return;
      final Map<String, dynamic> detail =
          (r[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> tmdb =
          (r[1] as Map<String, dynamic>?) ?? <String, dynamic>{};
      setState(() {
        _detail = detail;
        _tmdb = tmdb;
        _loading = false;
        // Auto-expand the most recent season.
        final List<dynamic> seasons =
            (detail['seasons'] as List<dynamic>?) ?? <dynamic>[];
        if (seasons.isNotEmpty) {
          _expandedSeasons
              .add((seasons.last as Map<String, dynamic>)['season'] as int? ?? 0);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── grab flow ────────────────────────────────────────────────────────────────

  Future<void> _grab() async {
    // ThePirateBay is an AI-access-only source. Non-AI users keep the original
    // single-source flow with no extra step.
    String source = 'prowlarr';
    if (Api.I.isSuperadmin) {
      final String? picked = await _pickSource();
      if (picked == null || !mounted) return;
      source = picked;
    }
    final String? language = await _pickLanguage();
    if (language == null || !mounted) return;
    final String? tier = await _pickQuality(language);
    if (tier == null || !mounted) return;
    await _doGrab(language, tier, source);
  }

  Future<String?> _pickSource() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
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
        );
      },
    );
  }

  Future<String?> _pickLanguage() {
    final bool hasEn = (_detail?['on_disk_en'] ?? _item['on_disk_en']) == true;
    final bool hasCs = (_detail?['on_disk_cs'] ?? _item['on_disk_cs']) == true;
    final String appLang = lang.value;
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
          final List<String> meta = <String>[
            if (isDefault) tr('appLanguage'),
            if (source != null) source,
          ];
          return ListTile(
            selected: isDefault,
            leading: Text(flag, style: const TextStyle(fontSize: 24)),
            title: Text(label),
            subtitle: meta.isNotEmpty
                ? Text(meta.join(' · '), style: const TextStyle(fontSize: 11))
                : null,
            trailing: onDisk
                ? const Icon(Icons.check_circle_outline,
                    color: Colors.green, size: 20)
                : null,
            onTap: () => Navigator.pop(ctx, code),
          );
        }

        final Widget enTile =
            tile(code: 'en', flag: '🇬🇧', label: tr('langEnglish'), onDisk: hasEn);
        final Widget csTile = tile(
            code: 'cs',
            flag: '🇨🇿',
            label: tr('langCzech'),
            source: 'sktorrent.eu',
            onDisk: hasCs);
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('pickLanguage'),
                      style: Theme.of(ctx).textTheme.titleMedium)),
            ),
            if (appLang == 'cs') ...<Widget>[csTile, enTile]
            else ...<Widget>[enTile, csTile],
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  Future<String?> _pickQuality(String language) {
    final String flag = language == 'cs' ? '🇨🇿' : '🇬🇧';
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
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
              leading: Icon(t == 'fast'
                  ? Icons.flash_on_outlined
                  : t == 'best'
                      ? Icons.star_outline
                      : Icons.balance_outlined),
              title: Text(tr(t)),
              onTap: () => Navigator.pop(ctx, t),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Modal with a spinner that cycles through grab stage messages while we wait.
  /// Mirrors the search-list flow so Download shows the same steps everywhere.
  /// The returned close callback is idempotent (safe to call more than once).
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
    bool closed = false;
    return () {
      if (closed) return;
      closed = true;
      timer.cancel();
      step.dispose();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    };
  }

  Future<void> _doGrab(String language, String tier, String source) async {
    setState(() => _grabbing = true);
    final VoidCallback closeStages = _showStages();
    final String itype = _item['type'] as String? ?? 'movie';
    try {
      final Map<String, dynamic> result = await Api.I.grab(
        type: itype,
        tmdbId: itype == 'movie' ? _item['tmdbId'] as int? : null,
        tvdbId: itype == 'tv' ? _item['tvdbId'] as int? : null,
        tier: tier,
        language: language,
        source: source,
      );
      closeStages();
      if (!mounted) return;
      if (result['no_czech_audio'] == true) {
        setState(() => _grabbing = false);
        await _offerFallback(
            tier,
            result['title']?.toString() ?? _item['title']?.toString() ?? '',
            source);
        return;
      }
      setState(() {
        if (language == 'cs') {
          _item['on_disk_cs'] = true;
          _detail?['on_disk_cs'] = true;
        } else {
          _item['on_disk_en'] = true;
          _detail?['on_disk_en'] = true;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          // Dismiss by swiping left or right (instead of the default downward swipe).
          dismissDirection: DismissDirection.horizontal,
          content:
              Text(itype == 'tv' ? tr('requestedTv') : tr('added'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('error'))));
      }
    } finally {
      closeStages();
      if (mounted) setState(() => _grabbing = false);
    }
  }

  Future<void> _offerFallback(String tier, String title, String source) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr('noCzechAudio')),
        content: Text(tr('noCzechAudioMsg')
            .replaceFirst('{title}', title)
            .replaceFirst('{tier}', tr(tier))),
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
    if (ok == true && mounted) await _doGrab('en', tier, source);
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final String title = _item['title'] as String? ?? '';
    final String? poster = _item['poster'] as String?;
    final String? backdropPath = _tmdb?['backdrop_path'] as String?;
    final String heroUrl =
        backdropPath != null ? '${_kImg}w1280$backdropPath' : (poster ?? '');

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 270,
            pinned: true,
            stretch: true,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const <StretchMode>[StretchMode.zoomBackground],
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 64, 14),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  shadows: <Shadow>[
                    Shadow(blurRadius: 8, color: Colors.black87)
                  ],
                ),
              ),
              background: heroUrl.isNotEmpty
                  ? Stack(fit: StackFit.expand, children: <Widget>[
                      CachedNetworkImage(
                        imageUrl: heroUrl,
                        fit: BoxFit.cover,
                        // Full-bleed, so no downscale here — but it is the single
                        // largest image in the app (w1280, 200-400 KB) and the one
                        // most worth not re-fetching every time a title is opened.
                        errorWidget: (_, __, ___) => _fallback(context),
                        placeholder: (_, __) => _fallback(context),
                        fadeOutDuration: Duration.zero,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.transparent,
                              Colors.black87
                            ],
                            stops: <double>[0.4, 1.0],
                          ),
                        ),
                      ),
                    ])
                  : _fallback(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
              child: _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest);

  Widget _body(BuildContext context) {
    final bool isMovie = _item['type'] == 'movie';
    final int? year = _item['year'] as int?;
    final String overview = (_detail?['overview'] as String?)?.isNotEmpty == true
        ? _detail!['overview'] as String
        : (_item['overview'] as String? ?? '');

    final List<dynamic> genres =
        (_detail?['genres'] as List<dynamic>?)?.isNotEmpty == true
            ? _detail!['genres'] as List<dynamic>
            : (_tmdb?['genres'] as List<dynamic>?) ?? <dynamic>[];

    final int? runtime =
        (_detail?['runtime'] as int?) ?? (_tmdb?['runtime'] as int?);
    final String? network = (_detail?['network'] as String?) ??
        ((_tmdb?['networks'] as List<dynamic>?)?.isNotEmpty == true
            ? ((_tmdb!['networks'] as List<dynamic>).first
                    as Map<String, dynamic>)['name'] as String?
            : null);
    final String? status = _detail?['status'] as String?;
    final double? rating = (_tmdb?['vote_average'] as num?)?.toDouble();

    final List<dynamic> countries =
        (_tmdb?['production_countries'] as List<dynamic>?) ?? <dynamic>[];
    final String countryStr = countries
        .map<String>((dynamic c) =>
            (c as Map<String, dynamic>)['iso_3166_1'] as String? ?? '')
        .where((String s) => s.isNotEmpty)
        .take(3)
        .join(', ');

    final Map<String, dynamic> credits =
        (_tmdb?['credits'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<dynamic> cast =
        (credits['cast'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> directors =
        ((credits['crew'] as List<dynamic>?) ?? <dynamic>[])
            .where((dynamic c) =>
                (c as Map<String, dynamic>)['job'] == 'Director')
            .toList();

    final bool hasEn = (_detail?['on_disk_en'] ?? _item['on_disk_en']) == true;
    final bool hasCs = (_detail?['on_disk_cs'] ?? _item['on_disk_cs']) == true;
    final bool inLibrary = hasEn && hasCs;

    final List<dynamic> seasons =
        (_detail?['seasons'] as List<dynamic>?) ?? <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ── Meta row ──────────────────────────────────────────────────────────
        Wrap(spacing: 14, runSpacing: 4, children: <Widget>[
          if (year != null)
            Text('$year',
                style: const TextStyle(fontWeight: FontWeight.w500)),
          if (rating != null && rating > 0)
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
              const SizedBox(width: 2),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ]),
          if (runtime != null && runtime > 0)
            Text(
              _fmtRuntime(runtime, isMovie),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          if (!isMovie && seasons.isNotEmpty)
            Text(
              '${seasons.length} ${seasons.length == 1 ? 'season' : 'seasons'}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ]),
        const SizedBox(height: 10),

        // ── Genre chips ───────────────────────────────────────────────────────
        if (genres.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: genres.take(6).map<Widget>((dynamic g) {
              final String name = g is Map
                  ? (g['name'] as String? ?? '')
                  : g.toString();
              return Chip(
                label:
                    Text(name, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],

        // ── Country / Network / Status ─────────────────────────────────────
        if (countryStr.isNotEmpty || network != null || status != null)
          Wrap(spacing: 16, runSpacing: 6, children: <Widget>[
            if (countryStr.isNotEmpty)
              _meta(context, Icons.flag_outlined, countryStr),
            if (!isMovie && network != null && network.isNotEmpty)
              _meta(context, Icons.tv, network),
            if (status != null && status.isNotEmpty)
              _meta(context, Icons.info_outline, status),
          ]),
        const SizedBox(height: 16),

        // ── Language chips + Download / In-library ─────────────────────────
        Row(children: <Widget>[
          if (hasEn) const Text('🇬🇧', style: TextStyle(fontSize: 20)),
          if (hasEn && hasCs) const SizedBox(width: 4),
          if (hasCs) const Text('🇨🇿', style: TextStyle(fontSize: 20)),
          if (hasEn || hasCs) const SizedBox(width: 10),
          if (inLibrary)
            Chip(
              avatar: const Icon(Icons.check_circle,
                  size: 16, color: Colors.green),
              label: Text(tr('inLibraryBoth'),
                  style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600)),
              backgroundColor:
                  Colors.green.withValues(alpha: 0.12),
              padding: EdgeInsets.zero,
            )
          else
            FilledButton.icon(
              onPressed: _grabbing ? null : _grab,
              icon: _grabbing
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download, size: 18),
              label: Text(tr('download')),
            ),
        ]),

        // ── Overview ──────────────────────────────────────────────────────────
        if (overview.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: overview.length > 220
                ? () => setState(
                    () => _overviewExpanded = !_overviewExpanded)
                : null,
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _overviewExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Text(overview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.55)),
              secondChild:
                  Text(overview, style: const TextStyle(height: 1.55)),
            ),
          ),
          if (overview.length > 220)
            TextButton(
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize:
                      MaterialTapTargetSize.shrinkWrap),
              onPressed: () => setState(
                  () => _overviewExpanded = !_overviewExpanded),
              child: Text(
                  _overviewExpanded ? tr('showLess') : tr('showMore')),
            ),
        ],

        // ── Director (movies only) ─────────────────────────────────────────
        if (isMovie && directors.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(tr('director'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            directors
                .take(2)
                .map<String>((dynamic d) =>
                    (d as Map<String, dynamic>)['name']
                        as String? ??
                    '')
                .join(', '),
            style: const TextStyle(fontSize: 13),
          ),
        ],

        // ── Cast ──────────────────────────────────────────────────────────────
        if (cast.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(tr('cast'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length > 15 ? 15 : cast.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 10),
              itemBuilder: (_, int i) => _castCard(
                  context, cast[i] as Map<String, dynamic>),
            ),
          ),
        ],

        // ── Seasons & Episodes (TV) ───────────────────────────────────────
        if (!isMovie && seasons.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(tr('seasons'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...seasons.map<Widget>((dynamic s) =>
              _seasonPanel(context, s as Map<String, dynamic>)),
        ],

        // ── Loading indicator ─────────────────────────────────────────────
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _meta(BuildContext context, IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon,
            size: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);

  Widget _castCard(BuildContext context, Map<String, dynamic> member) {
    final String? profilePath = member['profile_path'] as String?;
    final String name = member['name'] as String? ?? '';
    final String character = member['character'] as String? ?? '';
    return SizedBox(
      width: 74,
      child: Column(children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: profilePath != null
              ? CachedNetworkImage(
                  imageUrl: '${_kImg}w185$profilePath',
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  // 64 logical pixels; 192 covers 3x without decoding the full w185.
                  memCacheWidth: 192,
                  errorWidget: (_, __, ___) => _avatar(context, name),
                  placeholder: (_, __) => _avatar(context, name),
                  fadeOutDuration: Duration.zero,
                )
              : _avatar(context, name),
        ),
        const SizedBox(height: 5),
        Text(name,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w500)),
        if (character.isNotEmpty)
          Text(character,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9,
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _avatar(BuildContext context, String name) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      );

  Widget _seasonPanel(
      BuildContext context, Map<String, dynamic> s) {
    final int seasonNum = s['season'] as int? ?? 0;
    final List<dynamic> episodes =
        (s['episodes'] as List<dynamic>?) ?? <dynamic>[];
    final int total = episodes.length;
    final int downloaded = episodes
        .where((dynamic e) =>
            (e as Map<String, dynamic>)['has_file'] == true)
        .length;
    final bool expanded = _expandedSeasons.contains(seasonNum);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(children: <Widget>[
        InkWell(
          onTap: () => setState(() => expanded
              ? _expandedSeasons.remove(seasonNum)
              : _expandedSeasons.add(seasonNum)),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(children: <Widget>[
              Icon(
                  expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 20),
              const SizedBox(width: 8),
              Text('Season $seasonNum',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              // A season with a gap is called out in amber rather than the muted
              // onSurfaceVariant it used to share with ordinary secondary text —
              // which read as "nothing to see here" — and matches the missing-episode
              // badge on the library row, so incomplete looks the same everywhere.
              Text('$downloaded/$total',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: downloaded == total
                          ? FontWeight.normal
                          : FontWeight.w600,
                      color: downloaded == total ? Colors.green : Colors.amber)),
              const SizedBox(width: 4),
              Icon(
                  downloaded == total
                      ? Icons.download_done
                      : Icons.warning_amber_rounded,
                  size: 14,
                  color: downloaded == total ? Colors.green : Colors.amber),
            ]),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              children: episodes
                  .map<Widget>((dynamic e) => _episodeRow(
                      context, e as Map<String, dynamic>))
                  .toList(),
            ),
          ),
      ]),
    );
  }

  Widget _episodeRow(
      BuildContext context, Map<String, dynamic> ep) {
    final int? n = ep['n'] as int?;
    final String title = ep['title'] as String? ?? '';
    final bool hasFile = ep['has_file'] as bool? ?? false;
    final int? resolution = ep['resolution'] as int?;
    final String? quality = ep['quality'] as String?;
    final String airDate = ep['air_date'] as String? ?? '';

    Color? dotColor;
    if (hasFile) {
      if (resolution != null && resolution >= 1080) {
        dotColor = Colors.green;
      } else if (resolution != null && resolution >= 720) {
        dotColor = Colors.amber;
      } else {
        dotColor = Colors.redAccent;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                'E${n?.toString().padLeft(2, '0') ?? '??'}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    if (airDate.isNotEmpty)
                      Text(airDate,
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  ]),
            ),
            const SizedBox(width: 8),
            if (dotColor != null) ...<Widget>[
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: dotColor),
              ),
              if (quality != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 1),
                  child: Text(quality,
                      style:
                          TextStyle(fontSize: 9, color: dotColor)),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.radio_button_unchecked,
                    size: 10,
                    color: Theme.of(context).colorScheme.outline),
              ),
          ]),
    );
  }

  String _fmtRuntime(int minutes, bool isMovie) {
    if (!isMovie) return '${minutes}m / ep';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
