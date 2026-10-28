import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';

// Per-user mute switches (owner's notification review, #43). The gateway owns the list:
// GET /notifications/prefs returns one group per kind of user-facing notification
// ({id, label, label_cs, muted}) and PUT stores the muted ids. Server alerts for the
// admin are not in it -- they cannot be muted. Quiet hours (#42) are set here too (owner,
// 2026-10-28): on or off, from and until ("HH:MM"), on the phone's own clock -- the app
// tells the gateway its time zone (time_zone.dart). Notifications in them arrive
// silently, unless you asked for the thing during them.

typedef PrefsLoader = Future<Map<String, dynamic>> Function();
typedef PrefsSaver = Future<Map<String, dynamic>> Function(List<String> muted);
typedef QuietSaver = Future<Map<String, dynamic>> Function(Map<String, dynamic> quiet);

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.load, this.save, this.saveQuiet});

  /// Injectable for tests; default to the gateway.
  final PrefsLoader? load;
  final PrefsSaver? save;
  final QuietSaver? saveQuiet;

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  List<Map<String, dynamic>> _groups = <Map<String, dynamic>>[];
  Map<String, dynamic> _quiet = <String, dynamic>{'enabled': true, 'start': '23:00', 'end': '07:00'};
  String? _tz;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  PrefsLoader get _load => widget.load ?? Api.I.notificationPrefs;
  PrefsSaver get _save => widget.save ?? Api.I.setNotificationPrefs;
  QuietSaver get _saveQuiet => widget.saveQuiet ?? Api.I.setQuietHours;

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
      final Object? quiet = data['quiet'];
      if (quiet is Map<String, dynamic>) _quiet = quiet;
      _tz = data['tz']?.toString();
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

  Future<void> _setQuiet(Map<String, dynamic> change) async {
    final Map<String, dynamic> before = _quiet;
    setState(() {
      _saving = true;
      _quiet = <String, dynamic>{..._quiet, ...change};
    });
    try {
      _apply(await _saveQuiet(change));
    } catch (_) {
      if (!mounted) return;
      setState(() => _quiet = before);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('notificationSettingsError'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(String key) async {
    final List<String> hm = (_quiet[key]?.toString() ?? '00:00').split(':');
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(hm[0]) ?? 0, minute: int.tryParse(hm.last) ?? 0),
      builder: (BuildContext c, Widget? child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    await _setQuiet(<String, dynamic>{key: '${two(t.hour)}:${two(t.minute)}'});
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
                    SwitchListTile(
                      key: const ValueKey<String>('quiet-enabled'),
                      secondary: const Icon(Icons.bedtime_outlined),
                      title: Text(tr('quietHours')),
                      subtitle: Text(tr('quietHoursHint')),
                      value: _quiet['enabled'] != false,
                      onChanged: _saving ? null : (bool v) => _setQuiet(<String, dynamic>{'enabled': v}),
                    ),
                    if (_quiet['enabled'] != false) ...<Widget>[
                      ListTile(
                        key: const ValueKey<String>('quiet-start'),
                        contentPadding: const EdgeInsets.only(left: 72, right: 16),
                        title: Text(tr('quietFrom')),
                        trailing: Text('${_quiet['start']}', style: const TextStyle(fontSize: 16)),
                        onTap: _saving ? null : () => _pickTime('start'),
                      ),
                      ListTile(
                        key: const ValueKey<String>('quiet-end'),
                        contentPadding: const EdgeInsets.only(left: 72, right: 16),
                        title: Text(tr('quietUntil')),
                        trailing: Text('${_quiet['end']}', style: const TextStyle(fontSize: 16)),
                        onTap: _saving ? null : () => _pickTime('end'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
                        child: Text(
                            _tz == null ? tr('quietTimeZone') : '${tr('quietTimeZone')} ($_tz)',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      ),
                    ],
                  ],
                ),
    );
  }
}
