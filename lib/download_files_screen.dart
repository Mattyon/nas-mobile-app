import 'dart:async';

import 'package:flutter/material.dart';

import 'i18n.dart';

/// Every file of one download with its own progress, finished ones too: tap a season pack
/// in Downloads and see each episode (owner, 2026-11-23: "when I click on manifest.s01, I
/// want to see a screen showing all the episodes and their progress (even the ones that are
/// 100% downloaded)"). Rows come from the gateway's GET /downloads/{hash}/files: video files
/// in episode order, skipped bonus material left out. Refreshes every few seconds.
///
/// An episode already in the library (the NAS imports each one as soon as it is complete)
/// says so and gets a Watch button that opens it in Jellyfin (owner, 2026-11-23: "Watch
/// now" for episodes that arrived while the rest downloads).
class DownloadFilesScreen extends StatefulWidget {
  const DownloadFilesScreen({super.key, required this.title, required this.load, this.watch});

  final String title;

  /// Fetches the rows (Api.I.downloadFiles(hash) in the app).
  final Future<List<dynamic>> Function() load;

  /// Opens a Jellyfin item; no Watch buttons without it.
  final Future<Object?> Function(String jellyfinId)? watch;

  static const Duration refreshEvery = Duration(seconds: 3);

  @override
  State<DownloadFilesScreen> createState() => _DownloadFilesScreenState();
}

class _DownloadFilesScreenState extends State<DownloadFilesScreen> with LangAware {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(DownloadFilesScreen.refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> rows = await widget.load();
      if (!mounted) return;
      setState(() {
        _rows = rows.whereType<Map<String, dynamic>>().toList();
        _failed = false;
      });
    } catch (_) {
      // Keep the last rows on a failed refresh; say so only when there are none.
      if (mounted) setState(() => _failed = true);
    }
  }

  static String fmtBytes(num bytes) {
    final double b = bytes.toDouble();
    const double gb = 1024 * 1024 * 1024;
    if (b >= gb) return '${(b / gb).toStringAsFixed(1)} GB';
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  Widget _row(Map<String, dynamic> f) {
    final double pct = (f['progress'] as num?)?.toDouble() ?? 0;
    final bool done = pct >= 100;
    final String name = f['name']?.toString() ?? '';
    final String? episode = f['episode']?.toString();
    final num size = (f['size_bytes'] as num?) ?? 0;
    final num got = (f['downloaded_bytes'] as num?) ?? 0;
    final bool inLibrary = f['in_library'] == true;
    final String? jellyfinId = f['jellyfin_id']?.toString();
    return ListTile(
      leading: Icon(done ? Icons.check_circle : Icons.downloading,
          color: done ? Colors.green : Colors.grey),
      title: Text(episode ?? name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (episode != null)
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: pct / 100, color: done ? Colors.green : null),
        const SizedBox(height: 4),
        Text((done
                ? '100%  •  ${fmtBytes(size)}'
                : '${pct.toStringAsFixed(1)}%  •  ${fmtBytes(got)} / ${fmtBytes(size)}') +
            (inLibrary ? '  •  ${tr('filesInLibrary')}' : '')),
      ]),
      trailing: jellyfinId != null && widget.watch != null
          ? IconButton(
              icon: const Icon(Icons.play_circle_fill, size: 32),
              tooltip: tr('watchNow'),
              onPressed: () => widget.watch!(jellyfinId),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>>? rows = _rows;
    Widget body;
    if (rows == null) {
      body = Center(
          child: _failed ? Text(tr('filesError')) : const CircularProgressIndicator());
    } else if (rows.isEmpty) {
      body = Center(child: Text(tr('filesNone')));
    } else {
      final int done =
          rows.where((Map<String, dynamic> f) => ((f['progress'] as num?) ?? 0) >= 100).length;
      body = ListView(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(tr('filesDone')
              .replaceAll('{done}', '$done')
              .replaceAll('{total}', '${rows.length}')),
        ),
        ...rows.map(_row),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: body,
    );
  }
}
