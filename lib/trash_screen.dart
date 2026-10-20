import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';

// The trash bin (admin): titles deleted in the app stay in Radarr/Sonarr's recycle bin for
// a number of days (RECYCLE_BIN_DAYS on the NAS) and can be restored here until then.
// The gateway's GET /trash lists them; POST /trash/{id}/restore puts the files back and
// adds the title to Radarr/Sonarr again.

/// "1 day" / "3 days"; Czech "1 den" / "2 dny" / "5 dní". Never "day(s)".
String daysText(int n) {
  if (lang.value == 'cs') {
    return '$n ${n == 1 ? 'den' : (n >= 2 && n <= 4) ? 'dny' : 'dní'}';
  }
  return '$n ${n == 1 ? 'day' : 'days'}';
}

/// After a delete: "Moved to the trash. Deleted for good in 14 days."
String movedToTrashText(int days) => tr('movedToTrash').replaceAll('{days}', daysText(days));

typedef TrashLoader = Future<Map<String, dynamic>> Function();
typedef TrashRestorer = Future<Map<String, dynamic>> Function(String id);

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.load, this.restore});

  /// Injectable for tests; default to the gateway.
  final TrashLoader? load;
  final TrashRestorer? restore;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  String? _busy;

  TrashLoader get _load => widget.load ?? Api.I.trash;
  TrashRestorer get _restore => widget.restore ?? Api.I.restoreFromTrash;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final Map<String, dynamic> r = await _load();
      if (!mounted) return;
      setState(() {
        _items = ((r['items'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = tr('trashError'); });
    }
  }

  Future<void> _confirmRestore(Map<String, dynamic> item) async {
    final String title = _label(item);
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(tr('trashRestore')),
            content: Text(tr('trashRestoreConfirm').replaceAll('{title}', title)),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
              FilledButton(
                  key: const ValueKey<String>('trash-restore-confirm'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('trashRestore'))),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => _busy = item['id'].toString());
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await _restore(item['id'].toString());
      messenger.showSnackBar(SnackBar(content: Text(tr('trashRestored').replaceAll('{title}', title))));
      await _fetch();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('trashRestoreFailed').replaceAll('{e}', '$e'))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _label(Map<String, dynamic> item) {
    final Object? year = item['year'];
    return year == null ? '${item['title']}' : '${item['title']} ($year)';
  }

  String _subtitle(Map<String, dynamic> item) {
    final int left = (item['days_left'] as num?)?.toInt() ?? 0;
    final double gb = ((item['size'] as num?)?.toDouble() ?? 0) / 1e9;
    final DateTime when = DateTime.fromMillisecondsSinceEpoch(
        (((item['deleted_at'] as num?)?.toDouble() ?? 0) * 1000).round()).toLocal();
    final String date = '${when.day}. ${when.month}. ${when.year}';
    return <String>[
      if (gb > 0) '${gb.toStringAsFixed(1)} GB',
      tr('trashDeletedOn').replaceAll('{date}', date),
      left > 0 ? tr('trashLeft').replaceAll('{days}', daysText(left)) : tr('trashToday'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('trash'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _items.isEmpty
                  ? Center(child: Text(tr('trashEmpty'), style: const TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (BuildContext c, int i) {
                          final Map<String, dynamic> item = _items[i];
                          final String id = item['id'].toString();
                          return ListTile(
                            key: ValueKey<String>('trash-$id'),
                            leading: Icon(item['kind'] == 'movie' ? Icons.movie_outlined : Icons.tv),
                            title: Text(_label(item)),
                            subtitle: Text(_subtitle(item)),
                            trailing: _busy == id
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton.icon(
                                    key: ValueKey<String>('trash-restore-$id'),
                                    onPressed: _busy == null ? () => _confirmRestore(item) : null,
                                    icon: const Icon(Icons.restore),
                                    label: Text(tr('trashRestore')),
                                  ),
                          );
                        },
                      ),
                    ),
    );
  }
}
