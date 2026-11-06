import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';

// "Download when out" (owner, 2026-11-06): a title that is not released yet (Dune: Part
// Three) shows "When out" instead of Download, in the search list and on its page. The
// gateway (reminders.py) downloads it with the picked language and quality once a release
// exists, and says so at 12:00 on the phone's clock. Its list lives under Downloads in the
// menu, where a reminder can be cancelled.

typedef ReminderLoader = Future<List<dynamic>> Function();
typedef ReminderDeleter = Future<void> Function(String id);

const List<String> _monthsEn = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "16 Dec 2026" / "16. 12. 2026" from "2026-12-16"; null when it is not a date.
String? releaseDateText(Object? iso) {
  final DateTime? d = DateTime.tryParse(iso?.toString() ?? '');
  if (d == null) return null;
  return lang.value == 'cs'
      ? '${d.day}. ${d.month}. ${d.year}'
      : '${d.day} ${_monthsEn[d.month - 1]} ${d.year}';
}

/// Whether a search result or title is not out yet.
bool notOutYet(Map<String, dynamic> item) => item['upcoming'] == true;

/// The button's look: waiting already, or not yet set.
IconData reminderIcon(Map<String, dynamic> item) =>
    item['reminder'] == true ? Icons.alarm_on : Icons.alarm_add;
String reminderLabel(Map<String, dynamic> item) =>
    item['reminder'] == true ? tr('whenOutWaiting') : tr('whenOut');

int? _extId(Map<String, dynamic> item) =>
    (item['type'] == 'tv' ? item['tvdbId'] : item['tmdbId']) as int?;

/// Sets, changes or cancels the reminder for [item] (marks item['reminder']). The pickers
/// are the screen's own, the same Download uses. Returns whether anything changed.
Future<bool> reminderAction(
  BuildContext context,
  Map<String, dynamic> item, {
  required Future<String?> Function() pickLanguage,
  required Future<String?> Function(String language) pickQuality,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  if (item['reminder'] == true) {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(tr('reminderChange')),
            onTap: () => Navigator.pop(ctx, 'change'),
          ),
          ListTile(
            leading: const Icon(Icons.alarm_off),
            title: Text(tr('reminderCancel')),
            onTap: () => Navigator.pop(ctx, 'cancel'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return false;
    if (choice == 'cancel') {
      try {
        final List<dynamic> all = await Api.I.reminders();
        for (final dynamic r in all) {
          if (r is Map<String, dynamic> && r['type'] == item['type'] && r['status'] == 'waiting' &&
              (item['type'] == 'tv' ? r['tvdbId'] : r['tmdbId']) == _extId(item)) {
            await Api.I.deleteReminder(r['id'].toString());
          }
        }
        item['reminder'] = false;
        messenger.showSnackBar(SnackBar(content: Text(tr('reminderCancelled'))));
        return true;
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(tr('error'))));
        return false;
      }
    }
  }
  final String? language = await pickLanguage();
  if (language == null) return false;
  final String? tier = await pickQuality(language);
  if (tier == null) return false;
  try {
    await Api.I.addReminder(
        type: item['type']?.toString() ?? 'movie', extId: _extId(item), tier: tier, language: language);
    item['reminder'] = true;
    messenger.showSnackBar(SnackBar(
        content: Text(tr('reminderSet')),
        duration: const Duration(seconds: 6),
        dismissDirection: DismissDirection.horizontal));
    return true;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('error'))));
    return false;
  }
}

/// The list of this account's reminders, each with its state; cancel with the bin.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, this.load, this.delete});

  /// Injectable for tests; default to the gateway.
  final ReminderLoader? load;
  final ReminderDeleter? delete;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _failed = false;

  ReminderLoader get _load => widget.load ?? Api.I.reminders;
  ReminderDeleter get _delete => widget.delete ?? Api.I.deleteReminder;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final List<dynamic> r = await _load();
      if (!mounted) return;
      setState(() {
        _items = r.whereType<Map<String, dynamic>>().toList();
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> r) async {
    try {
      await _delete(r['id'].toString());
      if (!mounted) return;
      setState(() => _items.remove(r));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('reminderCancelled'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('error'))));
      }
    }
  }

  String _state(Map<String, dynamic> r) {
    switch (r['status']) {
      case 'started':
        return tr('reminderStarted');
      case 'notified':
        return tr('reminderDone');
    }
    final String? date = releaseDateText(r['release_date']);
    return date == null ? tr('reminderWaiting') : '${tr('reminderWaiting')} · ${tr('premiereOn').replaceAll('{date}', date)}';
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed) {
      body = Center(child: Text(tr('error')));
    } else if (_items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('remindersEmpty'), textAlign: TextAlign.center),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 16),
          children: <Widget>[
            for (final Map<String, dynamic> r in _items)
              ListTile(
                leading: Icon(r['status'] == 'waiting' ? Icons.alarm_on : Icons.download_done),
                title: Text(r['year'] != null ? '${r['title']} (${r['year']})' : '${r['title']}'),
                subtitle: Text(
                    '${_state(r)}\n${r['language'] == 'cs' ? '🇨🇿' : '🇬🇧'} ${tr(r['tier']?.toString() ?? 'balanced')}'),
                isThreeLine: true,
                trailing: r['status'] == 'waiting'
                    ? IconButton(
                        icon: const Icon(Icons.alarm_off),
                        tooltip: tr('reminderCancel'),
                        onPressed: () => _remove(r),
                      )
                    : null,
              ),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(tr('remindersTitle'))), body: body);
  }
}
