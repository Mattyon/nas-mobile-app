import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';

// Tailscale on or off (superadmin; owner, 2026-10-27: "so the PC is only accessible when I
// am away"). While Tailscale runs, the NAS shares the whole home network with the tailnet.
// The gateway's POST /tailscale writes a request that the NAS applies within a minute; GET
// /tailscale reports the real state. The app talks to the gateway through the Cloudflare
// tunnel, not through Tailscale, so Tailscale can be turned back on from anywhere.

typedef TailscaleLoader = Future<Map<String, dynamic>> Function();
typedef TailscaleSetter = Future<Map<String, dynamic>> Function(bool on);

class TailscaleScreen extends StatefulWidget {
  const TailscaleScreen({super.key, this.load, this.set, this.pollEvery = const Duration(seconds: 5)});

  /// Injectable for tests; default to the gateway.
  final TailscaleLoader? load;
  final TailscaleSetter? set;
  final Duration pollEvery;

  @override
  State<TailscaleScreen> createState() => _TailscaleScreenState();
}

class _TailscaleScreenState extends State<TailscaleScreen> with LangAware<TailscaleScreen> {
  Map<String, dynamic>? _st;
  String? _error;
  bool _sending = false;
  Timer? _poll;

  TailscaleLoader get _load => widget.load ?? Api.I.tailscale;
  TailscaleSetter get _set => widget.set ?? Api.I.setTailscale;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _apply(Map<String, dynamic> r) {
    setState(() { _st = r; _error = null; });
    // Refresh while the NAS has not applied the change yet.
    _poll?.cancel();
    if (r['pending'] != null) _poll = Timer(widget.pollEvery, _fetch);
  }

  Future<void> _fetch() async {
    try {
      final Map<String, dynamic> r = await _load();
      if (mounted) _apply(r);
    } catch (_) {
      if (mounted) setState(() => _error = tr('tailscaleError'));
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => _sending = true);
    try {
      final Map<String, dynamic> r = await _set(on);
      if (mounted) _apply(r);
    } catch (_) {
      if (mounted) setState(() => _error = tr('tailscaleError'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// What the switch shows: the pending choice while it is being applied, else the state.
  bool? get _shownOn {
    final Object? pending = _st?['pending'];
    if (pending == 'on') return true;
    if (pending == 'off') return false;
    return _st?['on'] as bool?;
  }

  String _stateText() {
    final Map<String, dynamic> st = _st!;
    if (st['pending'] != null) return tr('tailscaleSwitching');
    if (st['stale'] == true) return tr('tailscaleStale');
    if (st['error'] != null) return tr('tailscaleError');
    if (st['on'] == true) {
      return st['online'] == true ? tr('tailscaleOnline') : tr('tailscaleConnecting');
    }
    if (st['on'] == false) return tr('tailscaleOffText');
    return tr('tailscaleUnknown');
  }

  String? _changedText() {
    final Object? at = _st?['changed_at'];
    if (at is! num) return null;
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    final String when = '${t.day}.${t.month}. ${two(t.hour)}:${two(t.minute)}';
    return tr('tailscaleChanged')
        .replaceAll('{when}', when)
        .replaceAll('{by}', (_st?['changed_by'] ?? '—').toString());
  }

  @override
  Widget build(BuildContext context) {
    final bool? on = _shownOn;
    return Scaffold(
      appBar: AppBar(title: const Text('Tailscale')),
      body: _st == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SwitchListTile(
                  key: const ValueKey<String>('tailscale-switch'),
                  title: Text(tr('tailscaleRemoteAccess')),
                  subtitle: Text(_stateText()),
                  value: on ?? false,
                  onChanged: (_sending || _st!['pending'] != null || on == null) ? null : _toggle,
                ),
                if (_changedText() != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_changedText()!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(tr('tailscaleHint')),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
    );
  }
}
