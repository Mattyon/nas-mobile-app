import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';

// Per-user mute switches (owner's notification review, #43). The gateway owns the list:
// GET /notifications/prefs returns one group per kind of user-facing notification
// ({id, label, label_cs, muted}) and PUT stores the muted ids. Server alerts for the
// admin are not in it -- they cannot be muted. Quiet hours (#42) are explained here too:
// 23:00-07:00 those arrive silently, unless you asked for the thing during the night.

typedef PrefsLoader = Future<Map<String, dynamic>> Function();
typedef PrefsSaver = Future<Map<String, dynamic>> Function(List<String> muted);

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.load, this.save});

  /// Injectable for tests; default to the gateway.
  final PrefsLoader? load;
  final PrefsSaver? save;

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  List<Map<String, dynamic>> _groups = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  PrefsLoader get _load => widget.load ?? Api.I.notificationPrefs;
  PrefsSaver get _save => widget.save ?? Api.I.setNotificationPrefs;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      _apply(await _load());
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = tr('notificationSettingsError'); });
    }
  }

  void _apply(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _groups = ((data['groups'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      _loading = false;
      _error = null;
    });
  }

  Future<void> _toggle(String id, bool enabled) async {
    final List<Map<String, dynamic>> before = _groups;
    setState(() {
      _saving = true;
      _groups = <Map<String, dynamic>>[
        for (final Map<String, dynamic> g in _groups)
          g['id'] == id ? <String, dynamic>{...g, 'muted': !enabled} : g,
      ];
    });
    final List<String> muted = <String>[
      for (final Map<String, dynamic> g in _groups)
        if (g['muted'] == true) g['id'].toString(),
    ];
    try {
      _apply(await _save(muted));
    } catch (_) {
      if (!mounted) return;
      setState(() => _groups = before);   // put the switch back: nothing was saved
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('notificationSettingsError'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool cs = lang.value == 'cs';
    return Scaffold(
      appBar: AppBar(title: Text(tr('notificationSettings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : ListView(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(tr('notificationSettingsHint'),
                          style: TextStyle(color: Colors.grey[500])),
                    ),
                    for (final Map<String, dynamic> g in _groups)
                      SwitchListTile(
                        key: ValueKey<String>('notif-${g['id']}'),
                        title: Text((cs ? g['label_cs'] : g['label'])?.toString() ??
                            g['id'].toString()),
                        value: g['muted'] != true,
                        onChanged: _saving ? null : (bool v) => _toggle(g['id'].toString(), v),
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.bedtime_outlined),
                      title: Text(tr('quietHours')),
                      subtitle: Text(tr('quietHoursHint')),
                    ),
                  ],
                ),
    );
  }
}
