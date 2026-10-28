import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/tab_history.dart';

void main() {
  late ValueNotifier<int> tab;
  late TabHistory h;

  setUp(() {
    tab = ValueNotifier<int>(0);
    h = TabHistory(tab);
  });
  tearDown(() => h.dispose());

  test('search, then downloads from the toast: back returns to the search', () {
    tab.value = 1;
    expect(h.canGoBack, isTrue);
    h.back();
    expect(tab.value, 0);
    expect(h.canGoBack, isFalse); // the next back leaves the app
  });

  test('walks back through every tab visited, in order', () {
    tab.value = 2;
    tab.value = 1;
    h.back();
    expect(tab.value, 2);
    h.back();
    expect(tab.value, 0);
  });

  test('going back is not itself recorded', () {
    tab.value = 1;
    h.back();
    h.back(); // nothing left: stays on search
    expect(tab.value, 0);
    expect(h.canGoBack, isFalse);
  });

  test('opened straight on another tab: back goes to search first', () {
    tab.value = 2;
    final TabHistory fresh = TabHistory(tab);
    expect(fresh.canGoBack, isTrue);
    fresh.back();
    expect(tab.value, 0);
    fresh.dispose();
  });
}
