import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';

const String _kImg = 'https://image.tmdb.org/t/p/';

// The show detail used to list seasons only for shows already in Sonarr (its
// /detail payload is the sole source), so a show found in search showed nothing
// but "22m / ep · continuing". Seasons and episodes now come from TMDb for every
// show; Sonarr's per-episode file status is laid over them when the show is in
// the library.

// ── merging (pure, tested) ─────────────────────────────────────────────────────

/// One row per season: TMDb's facts (name, poster, air date, episode count),
/// plus Sonarr's `episodes`, `have` and `total` when the show is in the library.
/// Regular seasons ascend; Specials (season 0) go last. TMDb's empty placeholder
/// seasons (announced, no episodes listed yet) are dropped — there is nothing to
/// open — unless Sonarr knows episodes for them.
List<Map<String, dynamic>> mergeSeasons(
    List<dynamic> tmdbSeasons, List<dynamic> sonarrSeasons) {
  final Map<int, Map<String, dynamic>> out = <int, Map<String, dynamic>>{};
  for (final dynamic raw in tmdbSeasons) {
    final Map<String, dynamic> t = raw as Map<String, dynamic>;
    final int n = t['season_number'] as int? ?? 0;
    out[n] = <String, dynamic>{
      'season': n,
      'name': t['name'],
      'air_date': t['air_date'],
      'episode_count': t['episode_count'] as int? ?? 0,
      'poster_path': t['poster_path'],
      'overview': t['overview'],
    };
  }
  for (final dynamic raw in sonarrSeasons) {
    final Map<String, dynamic> s = raw as Map<String, dynamic>;
    final int n = s['season'] as int? ?? 0;
    final List<dynamic> eps = (s['episodes'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> row = out.putIfAbsent(
        n, () => <String, dynamic>{'season': n, 'episode_count': eps.length});
    row['episodes'] = eps;
    row['total'] = eps.length;
    row['have'] = eps
        .where((dynamic e) => (e as Map<String, dynamic>)['has_file'] == true)
        .length;
  }
  final List<Map<String, dynamic>> list = out.values
      .where((Map<String, dynamic> s) =>
          (s['episode_count'] as int? ?? 0) > 0 || s['total'] != null)
      .toList();
  list.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int x = a['season'] as int, y = b['season'] as int;
    if (x == 0 || y == 0) return x == 0 ? 1 : -1;
    return x.compareTo(y);
  });
  return list;
}

// TMDb answers a missing translation with a numbered placeholder ("Epizoda 3")
// rather than an empty name, so "has a title" needs this check, not isNotEmpty.
final RegExp _placeholderTitle =
    RegExp(r'^(episode|epizoda|díl|folge)\s*\d+$', caseSensitive: false);

String? _realTitle(Object? v) {
  final String s = (v as String? ?? '').trim();
  return s.isEmpty || _placeholderTitle.hasMatch(s) ? null : s;
}

String? _nonEmpty(Object? v) {
  final String s = (v as String? ?? '').trim();
  return s.isEmpty ? null : s;
}

/// Episodes of one season. [tmdb] is in the app language; [fallback] is the same
/// season in English, used field by field where Czech has no translation (empty
/// for an English app). [sonarr] is null when the show is not in the library —
/// then no episode claims to be on disk or missing.
List<Map<String, dynamic>> mergeEpisodes(
    List<dynamic> tmdb, List<dynamic> fallback, List<dynamic>? sonarr) {
  Map<int, Map<String, dynamic>> byNumber(List<dynamic> eps, String key) =>
      <int, Map<String, dynamic>>{
        for (final dynamic e in eps)
          ((e as Map<String, dynamic>)[key] as int? ?? 0): e,
      };
  final Map<int, Map<String, dynamic>> en = byNumber(fallback, 'episode_number');
  final Map<int, Map<String, dynamic>> files =
      byNumber(sonarr ?? <dynamic>[], 'n');
  final bool inLibrary = sonarr != null;

  Map<String, dynamic> row(int n, Map<String, dynamic> t) {
    final Map<String, dynamic> e = en[n] ?? <String, dynamic>{};
    final Map<String, dynamic> f = files[n] ?? <String, dynamic>{};
    final num? votes = t['vote_count'] as num?;
    return <String, dynamic>{
      'n': n,
      'title': _realTitle(t['name']) ??
          _realTitle(e['name']) ??
          _nonEmpty(f['title']) ??
          tr('episodeN').replaceAll('{n}', '$n'),
      'overview': _nonEmpty(t['overview']) ?? _nonEmpty(e['overview']),
      'still_path': t['still_path'] ?? e['still_path'],
      'air_date': _nonEmpty(t['air_date']) ?? _nonEmpty(f['air_date']),
      'runtime': t['runtime'] as int?,
      'rating': votes != null && votes > 0
          ? (t['vote_average'] as num?)?.toDouble()
          : null,
      'in_library': inLibrary,
      'has_file': f['has_file'] == true,
      'quality': f['quality'],
      'resolution': f['resolution'],
    };
  }

  final Map<int, Map<String, dynamic>> out = <int, Map<String, dynamic>>{};
  for (final dynamic raw in tmdb) {
    final Map<String, dynamic> t = raw as Map<String, dynamic>;
    final int n = t['episode_number'] as int? ?? 0;
    out[n] = row(n, t);
  }
  // Episodes Sonarr has but TMDb does not list (numbering differences, very new
  // episodes) are still shown, from Sonarr's own fields.
  for (final MapEntry<int, Map<String, dynamic>> f in files.entries) {
    out.putIfAbsent(f.key, () => row(f.key, <String, dynamic>{}));
  }
  return out.values.toList()
    ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        (a['n'] as int).compareTo(b['n'] as int));
}

/// True for an episode that has not aired yet. No date at all counts as not
/// aired: TMDb lists announced episodes before they are scheduled.
bool isUpcoming(String? airDate, {DateTime? now}) {
  final DateTime? d = DateTime.tryParse(airDate ?? '');
  if (d == null) return true;
  final DateTime today = now ?? DateTime.now();
  return d.isAfter(DateTime(today.year, today.month, today.day));
}

const List<String> _monthsEn = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2019-05-03" → "3 May 2019" (EN) / "3. 5. 2019" (CS). Unparseable input is
/// returned unchanged.
String formatAirDate(String iso) {
  final DateTime? d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return lang.value == 'cs'
      ? '${d.day}. ${d.month}. ${d.year}'
      : '${d.day} ${_monthsEn[d.month - 1]} ${d.year}';
}

/// "Season 3", or TMDb's own name for Specials (season 0).
String seasonLabel(Map<String, dynamic> s) {
  final int n = s['season'] as int? ?? 0;
  return n == 0 ? tr('specials') : tr('seasonN').replaceAll('{n}', '$n');
}

/// The quality dot: green 1080p+, amber 720p, red below; null when no file.
Color? qualityDotColor(bool hasFile, int? resolution) {
  if (!hasFile) return null;
  if (resolution != null && resolution >= 1080) return Colors.green;
  if (resolution != null && resolution >= 720) return Colors.amber;
  return Colors.redAccent;
}

// ── season row on the show detail ──────────────────────────────────────────────

class SeasonTile extends StatelessWidget {
  const SeasonTile({super.key, required this.season, required this.onTap});
  final Map<String, dynamic> season;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? poster = season['poster_path'] as String?;
    final String year = (season['air_date'] as String? ?? '').length >= 4
        ? (season['air_date'] as String).substring(0, 4)
        : '';
    final int count = season['episode_count'] as int? ?? 0;
    final int? have = season['have'] as int?;
    final int? total = season['total'] as int?;
    final bool complete = have != null && have == total;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40,
                height: 60,
                child: poster != null
                    ? CachedNetworkImage(
                        imageUrl: '${_kImg}w92$poster',
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                        errorWidget: (_, __, ___) =>
                            ColoredBox(color: cs.surfaceContainerHighest),
                        placeholder: (_, __) =>
                            ColoredBox(color: cs.surfaceContainerHighest),
                        fadeOutDuration: Duration.zero,
                      )
                    : ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.tv, size: 18, color: cs.outline)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(seasonLabel(season),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        <String>[
                          if (year.isNotEmpty) year,
                          if (count > 0) trCount('episodes', count),
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
            ),
            // Same amber-for-a-gap badge as before, so incomplete looks the same
            // here, on the season screen and on the library row.
            if (have != null && total != null) ...<Widget>[
              Text('$have/$total',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          complete ? FontWeight.normal : FontWeight.w600,
                      color: complete ? Colors.green : Colors.amber)),
              const SizedBox(width: 4),
              Icon(complete ? Icons.download_done : Icons.warning_amber_rounded,
                  size: 14, color: complete ? Colors.green : Colors.amber),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: cs.outline),
          ]),
        ),
      ),
    );
  }
}

// ── season screen ──────────────────────────────────────────────────────────────

/// Loads one season from TMDb in a language ('cs-CZ' / 'en-US'). Injectable so
/// tests run without the network.
typedef SeasonLoader = Future<Map<String, dynamic>> Function(
    int season, String language);

class SeasonScreen extends StatefulWidget {
  const SeasonScreen({
    super.key,
    required this.showTitle,
    required this.tmdbId,
    required this.season,
    this.loader,
  });
  final String showTitle;
  final int tmdbId;
  /// A row from [mergeSeasons].
  final Map<String, dynamic> season;
  final SeasonLoader? loader;

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> with LangAware {
  List<Map<String, dynamic>> _episodes = <Map<String, dynamic>>[];
  String? _overview;
  bool _loading = true;
  bool _failed = false;

  int get _number => widget.season['season'] as int? ?? 0;
  List<dynamic>? get _sonarr => widget.season['episodes'] as List<dynamic>?;

  @override
  void initState() {
    super.initState();
    _overview = _nonEmpty(widget.season['overview']);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    if (widget.tmdbId <= 0) {
      // No TMDb match: Sonarr's list is all there is.
      setState(() {
        _episodes = mergeEpisodes(<dynamic>[], <dynamic>[], _sonarr);
        _loading = false;
      });
      return;
    }
    final SeasonLoader load = widget.loader ??
        (int s, String l) => Api.I.tmdbSeason(widget.tmdbId, s, language: l);
    final bool czech = lang.value == 'cs';
    try {
      final List<Map<String, dynamic>> r =
          await Future.wait<Map<String, dynamic>>(<Future<Map<String, dynamic>>>[
        load(_number, czech ? 'cs-CZ' : 'en-US'),
        if (czech) load(_number, 'en-US'),
      ]);
      if (!mounted) return;
      final Map<String, dynamic> primary = r[0];
      final Map<String, dynamic> english =
          czech ? r[1] : <String, dynamic>{};
      setState(() {
        _episodes = mergeEpisodes(
          (primary['episodes'] as List<dynamic>?) ?? <dynamic>[],
          (english['episodes'] as List<dynamic>?) ?? <dynamic>[],
          _sonarr,
        );
        _overview = _nonEmpty(primary['overview']) ??
            _nonEmpty(english['overview']) ??
            _overview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Still show what Sonarr knows rather than an empty screen.
        _episodes = mergeEpisodes(<dynamic>[], <dynamic>[], _sonarr);
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.showTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Text(seasonLabel(widget.season)),
            ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _header(context),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: <Widget>[
                Icon(Icons.cloud_off, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('seasonLoadFailed'))),
                TextButton(onPressed: _load, child: Text(tr('retry'))),
              ]),
            ),
          ..._episodes.map<Widget>((Map<String, dynamic> e) => EpisodeTile(
                episode: e,
                onTap: () => showEpisodeSheet(context, e, _number),
              )),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? poster = widget.season['poster_path'] as String?;
    final String airDate = widget.season['air_date'] as String? ?? '';
    final int count = _episodes.isNotEmpty
        ? _episodes.length
        : widget.season['episode_count'] as int? ?? 0;
    final int? have = widget.season['have'] as int?;
    final int? total = widget.season['total'] as int?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              if (poster != null) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: '${_kImg}w185$poster',
                    width: 80,
                    height: 120,
                    fit: BoxFit.cover,
                    memCacheWidth: 240,
                    errorWidget: (_, __, ___) => const SizedBox(width: 80),
                    fadeOutDuration: Duration.zero,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (airDate.isNotEmpty)
                        Text(formatAirDate(airDate),
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      if (count > 0)
                        Text(trCount('episodes', count),
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      if (have != null && total != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                              tr('episodesDownloaded')
                                  .replaceAll('{have}', '$have')
                                  .replaceAll('{total}', '$total'),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: have == total
                                      ? Colors.green
                                      : Colors.amber)),
                        ),
                    ]),
              ),
            ]),
            if (_overview != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_overview!, style: const TextStyle(height: 1.5)),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
          ]),
    );
  }
}

// ── episode row + detail sheet ─────────────────────────────────────────────────

class EpisodeTile extends StatelessWidget {
  const EpisodeTile({super.key, required this.episode, required this.onTap});
  final Map<String, dynamic> episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int n = episode['n'] as int? ?? 0;
    final String? still = episode['still_path'] as String?;
    final String? overview = episode['overview'] as String?;
    final bool upcoming = isUpcoming(episode['air_date'] as String?);

    return Opacity(
      // Not-yet-aired episodes are listed but quieter: they are news, not gaps.
      opacity: upcoming ? 0.6 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 112,
                    height: 63,
                    child: still != null
                        ? CachedNetworkImage(
                            imageUrl: '${_kImg}w300$still',
                            fit: BoxFit.cover,
                            memCacheWidth: 336,
                            errorWidget: (_, __, ___) => _stillPlaceholder(cs, n),
                            placeholder: (_, __) => _stillPlaceholder(cs, n),
                            fadeOutDuration: Duration.zero,
                          )
                        : _stillPlaceholder(cs, n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('$n. ${episode['title']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(episodeMeta(episode),
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                        if (overview != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(overview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        ],
                      ]),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _FileDot(episode: episode, upcoming: upcoming),
                ),
              ]),
        ),
      ),
    );
  }
}

Widget _stillPlaceholder(ColorScheme cs, int n) => ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
          child: Text('E${n.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
    );

/// "3 May 2019 · 42m · ★ 8.1", or "Airs 3 May 2026" for an upcoming episode.
String episodeMeta(Map<String, dynamic> e) {
  final String airDate = e['air_date'] as String? ?? '';
  if (isUpcoming(airDate)) {
    return airDate.isEmpty
        ? tr('notYetAired')
        : tr('airsOn').replaceAll('{date}', formatAirDate(airDate));
  }
  final int? runtime = e['runtime'] as int?;
  final double? rating = e['rating'] as double?;
  return <String>[
    formatAirDate(airDate),
    if (runtime != null && runtime > 0) '${runtime}m',
    if (rating != null) '★ ${rating.toStringAsFixed(1)}',
  ].join(' · ');
}

/// Quality dot for a file on disk, an empty ring for an aired episode the
/// library is missing, nothing when the show is not in the library or the
/// episode has not aired.
class _FileDot extends StatelessWidget {
  const _FileDot({required this.episode, required this.upcoming});
  final Map<String, dynamic> episode;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    if (episode['in_library'] != true) return const SizedBox.shrink();
    final Color? color = qualityDotColor(
        episode['has_file'] == true, episode['resolution'] as int?);
    if (color == null) {
      return upcoming
          ? const SizedBox.shrink()
          : Icon(Icons.radio_button_unchecked,
              size: 10, color: Theme.of(context).colorScheme.outline);
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

Future<void> showEpisodeSheet(
    BuildContext context, Map<String, dynamic> e, int season) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ScrollController scroll) =>
          EpisodeDetail(episode: e, season: season, controller: scroll),
    ),
  );
}

class EpisodeDetail extends StatelessWidget {
  const EpisodeDetail(
      {super.key, required this.episode, required this.season, this.controller});
  final Map<String, dynamic> episode;
  final int season;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int n = episode['n'] as int? ?? 0;
    final String? still = episode['still_path'] as String?;
    final String? overview = episode['overview'] as String?;
    final bool hasFile = episode['has_file'] == true;
    final String? quality = episode['quality'] as String?;
    final Color? dot = qualityDotColor(hasFile, episode['resolution'] as int?);
    final String code =
        'S${season.toString().padLeft(2, '0')} · E${n.toString().padLeft(2, '0')}';

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: <Widget>[
        if (still != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: '${_kImg}w780$still',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    ColoredBox(color: cs.surfaceContainerHighest),
                placeholder: (_, __) =>
                    ColoredBox(color: cs.surfaceContainerHighest),
                fadeOutDuration: Duration.zero,
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(code,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(episode['title'] as String? ?? '',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(episodeMeta(episode),
            style: TextStyle(color: cs.onSurfaceVariant)),
        if (episode['in_library'] == true) ...<Widget>[
          const SizedBox(height: 10),
          Row(children: <Widget>[
            if (dot != null)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              )
            else
              Icon(Icons.radio_button_unchecked, size: 12, color: cs.outline),
            const SizedBox(width: 8),
            Text(
                hasFile
                    ? (quality != null
                        ? tr('onDiskQuality').replaceAll('{q}', quality)
                        : tr('onDisk'))
                    : tr('notOnDisk'),
                style: TextStyle(
                    fontSize: 13, color: dot ?? cs.onSurfaceVariant)),
          ]),
        ],
        const SizedBox(height: 14),
        Text(overview ?? tr('noOverview'),
            style: TextStyle(
                height: 1.55,
                fontStyle: overview == null ? FontStyle.italic : null,
                color: overview == null ? cs.onSurfaceVariant : null)),
      ],
    );
  }
}
