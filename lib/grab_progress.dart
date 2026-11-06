import 'dart:async';
import 'package:flutter/material.dart';
import 'i18n.dart';

/// The progress of a download request ("Fetching torrents…" … "Starting the download…"),
/// shown as a snackbar at the bottom, like the "Added to downloads" that follows it.
///
/// It used to be a dialog, which blocked the app until the gateway answered; now the
/// search, the library and other titles stay usable, and several downloads can be started
/// one after another. One snackbar serves all requests in flight ("Starting 2
/// downloads"); the first to finish replaces it with its result.
class GrabProgress {
  GrabProgress._();

  static const Duration stepEvery = Duration(milliseconds: 1600);
  static const List<String> stageKeys = <String>[
    'stageSearch', 'stageDatabases', 'stagePick', 'stageStart',
  ];

  static int _active = 0;
  static final ValueNotifier<int> _step = ValueNotifier<int>(0);
  static final ValueNotifier<int> _count = ValueNotifier<int>(0);
  static Timer? _timer;
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bar;

  /// Requests still waiting for the gateway.
  static int get active => _active;

  /// Shows the progress, or counts one more request into it. The returned callback ends
  /// this request's part (idempotent); call it before showing the result.
  static VoidCallback start(ScaffoldMessengerState messenger) {
    _active++;
    _count.value = _active;
    _step.value = 0;
    _timer?.cancel();
    _timer = Timer.periodic(stepEvery, (_) {
      if (_step.value < stageKeys.length - 1) _step.value++;
    });
    if (_bar == null) {
      // Whatever is showing (an earlier "Added to downloads") gives way at once, without
      // its exit animation: the progress must be the current snackbar from the start, as
      // closing it (done()) acts on the current one.
      messenger.clearSnackBars();
      messenger.removeCurrentSnackBar();
      final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> bar =
          messenger.showSnackBar(SnackBar(
        content: const _ProgressContent(),
        duration: const Duration(minutes: 5),
        // Swipe it away like the result; the request carries on.
        dismissDirection: DismissDirection.horizontal,
      ));
      _bar = bar;
      bar.closed.then((_) {
        if (identical(_bar, bar)) _bar = null;
      });
    }
    bool done = false;
    return () {
      if (done) return;
      done = true;
      _active--;
      _count.value = _active;
      if (_active == 0) {
        _timer?.cancel();
        _timer = null;
      }
      final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? bar = _bar;
      _bar = null;
      bar?.close();
    };
  }
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent();

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onInverseSurface;
    return Row(children: <Widget>[
      SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
      const SizedBox(width: 14),
      Expanded(
        child: ValueListenableBuilder<int>(
          valueListenable: GrabProgress._count,
          builder: (_, int n, _) => ValueListenableBuilder<int>(
            valueListenable: GrabProgress._step,
            builder: (_, int i, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(tr(GrabProgress.stageKeys[i])),
                if (n > 1)
                  Text(tr('grabsStarting').replaceFirst('{n}', '$n'),
                      style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}
