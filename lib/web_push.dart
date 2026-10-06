import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';
import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart' as impl;

// Web Push for the web build (an iPhone home-screen app, or any browser). The Android
// app gets pushes through ntfy; a browser cannot keep that stream when closed. The
// gateway (web_push.py) sends every notification to the browsers its user subscribed.

enum PushState { unsupported, needsHomeScreen, denied, on, off }

PushState pushStateFrom(String s) => switch (s) {
      'needs-home-screen' => PushState.needsHomeScreen,
      'denied' => PushState.denied,
      'on' => PushState.on,
      'off' => PushState.off,
      _ => PushState.unsupported,
    };

abstract class WebPush {
  Future<PushState> state();
  Future<PushState> enable(String token, String lang);
  Future<PushState> disable(String token);
}

/// The browser implementation on the web, a stub (always unsupported) elsewhere.
/// Replaceable in tests.
WebPush webPush = impl.create();

Future<void> showWebPushDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const WebPushDialog());

class WebPushDialog extends StatefulWidget {
  const WebPushDialog({super.key});

  @override
  State<WebPushDialog> createState() => _WebPushDialogState();
}

class _WebPushDialogState extends State<WebPushDialog> with LangAware {
  PushState? _state;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    webPush.state().then((PushState s) {
      if (mounted) setState(() => _state = s);
    }).catchError((Object e) {
      if (mounted) setState(() => _state = PushState.unsupported);
    });
  }

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String token = Api.I.token ?? '';
      // enable() runs Notification.requestPermission(); iOS only allows that inside the
      // tap, so nothing may be awaited before this call.
      final PushState s = _state == PushState.on
          ? await webPush.disable(token)
          : await webPush.enable(token, lang.value);
      if (mounted) setState(() => _state = s);
    } catch (e) {
      if (mounted) setState(() => _error = tr('webPushError').replaceAll('{e}', '$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PushState? s = _state;
    final String text = switch (s) {
      null => '',
      PushState.on => tr('webPushOn'),
      PushState.off => tr('webPushOff'),
      PushState.denied => tr('webPushDenied'),
      PushState.needsHomeScreen => tr('webPushHomeScreen'),
      PushState.unsupported => tr('webPushUnsupported'),
    };
    final bool canToggle = s == PushState.on || s == PushState.off;
    return AlertDialog(
      title: Text(tr('webPush')),
      content: s == null
          ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
              Text(text),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('close'))),
        if (canToggle)
          FilledButton(
            onPressed: _busy ? null : _toggle,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s == PushState.on ? tr('webPushTurnOff') : tr('webPushTurnOn')),
          ),
      ],
    );
  }
}
