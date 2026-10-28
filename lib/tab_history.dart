import 'package:flutter/foundation.dart';

// The phone's back button walks back through the tabs (owner, 2026-10-28: search "scary
// movie 2", download it, open Downloads from the toast, press back: the search page again,
// with the same text and results). The search itself stays alive while another tab shows
// (HomeShell keeps it offstage), so going back finds it as it was.

class TabHistory {
  TabHistory(this.tab) : _last = tab.value {
    tab.addListener(_changed);
  }

  final ValueNotifier<int> tab;
  final List<int> _stack = <int>[];
  int _last;
  bool _goingBack = false;

  static const int _max = 20;

  void _changed() {
    if (!_goingBack && tab.value != _last) {
      _stack.add(_last);
      if (_stack.length > _max) _stack.removeAt(0);
    }
    _last = tab.value;
  }

  /// False when back should leave the app: nothing visited before, already on Search.
  bool get canGoBack => _stack.isNotEmpty || tab.value != 0;

  /// The previous tab; Search when there is none.
  void back() {
    _goingBack = true;
    tab.value = _stack.isNotEmpty ? _stack.removeLast() : 0;
    _goingBack = false;
  }

  void dispose() => tab.removeListener(_changed);
}
