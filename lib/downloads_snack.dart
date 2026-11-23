import 'package:flutter/material.dart';

/// The bottom overlay with a Downloads button ("Added to downloads", "Requested").
///
/// Once the Downloads tab is opened -- the bottom bar, the button itself, a notification --
/// these have said what they had to: the one on screen goes, and any still queued behind it
/// never appear (owner, 2026-11-23: "once i switch manually to downloads sections, all
/// notifications with the go to downloads link should disappear ... those bottom overlays").
///
/// A queued snackbar is not built until its turn, so it cannot watch the tab itself: each
/// remembers how many times Downloads had been opened when it was made, and gives way as
/// soon as it is on screen and that number has moved on. Other snackbars (errors, the
/// download request's progress) are left alone.
class DownloadsSnack {
  DownloadsSnack._();

  /// How many times the Downloads tab has been opened.
  static final ValueNotifier<int> opened = ValueNotifier<int>(0);

  /// Call whenever the Downloads tab becomes the selected one.
  static void downloadsOpened() => opened.value++;

  /// The snackbar: [message] with a [label] button that runs [onOpen].
  static SnackBar build(String message, {required String label, required VoidCallback onOpen}) =>
      SnackBar(
        content: _Content(message: message, madeAt: opened.value),
        duration: const Duration(seconds: 6),
        // Dismiss by swiping left or right (instead of the default downward swipe).
        dismissDirection: DismissDirection.horizontal,
        action: SnackBarAction(label: label, onPressed: onOpen),
      );
}

class _Content extends StatefulWidget {
  const _Content({required this.message, required this.madeAt});

  final String message;
  final int madeAt;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  bool _gone = false;
  late final bool _staleAtStart = DownloadsSnack.opened.value != widget.madeAt;

  @override
  void initState() {
    super.initState();
    DownloadsSnack.opened.addListener(_opened);
    // Queued while Downloads was opened: leave at once, without the exit animation.
    if (_staleAtStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave(animate: false));
    }
  }

  @override
  void dispose() {
    DownloadsSnack.opened.removeListener(_opened);
    super.dispose();
  }

  void _opened() => _leave(animate: true);

  void _leave({required bool animate}) {
    if (_gone || !mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _gone = true;
    animate ? messenger.hideCurrentSnackBar() : messenger.removeCurrentSnackBar();
  }

  // One that was stale when it came up is removed after its first frame; its text never
  // shows. One that goes while on screen keeps its text as it slides away.
  @override
  Widget build(BuildContext context) =>
      _staleAtStart ? const SizedBox.shrink() : Text(widget.message);
}
