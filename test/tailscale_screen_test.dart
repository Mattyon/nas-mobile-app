import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/tailscale_screen.dart';

Map<String, dynamic> st({bool? on = true, String? pending, bool stale = false, bool online = true,
        Object? changedAt, String? changedBy}) =>
    <String, dynamic>{
      'on': on, 'backend': on == true ? 'Running' : 'Stopped', 'online': online,
      'routes': <String>['192.168.50.0/24'], 'pending': pending, 'stale': stale,
      'changed_at': changedAt, 'changed_by': changedBy, 'error': null,
    };

Widget host(Widget w) => MaterialApp(home: w);

void main() {
  setUp(() => lang.value = 'en');

  testWidgets('shows the state and turns it off', (WidgetTester t) async {
    final List<bool> sent = <bool>[];
    await t.pumpWidget(host(TailscaleScreen(
      load: () async => st(),
      set: (bool on) async { sent.add(on); return st(pending: on ? 'on' : 'off'); },
      pollEvery: const Duration(hours: 1),
    )));
    await t.pumpAndSettle();
    expect(find.text('On: the home network is reachable over Tailscale'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('tailscale-switch')));
    await t.pumpAndSettle();
    expect(sent, <bool>[false]);
    expect(find.text('Switching… the NAS applies it within a minute'), findsOneWidget);
    // while pending, the switch shows the choice and cannot be flipped again
    final SwitchListTile s = t.widget(find.byKey(const ValueKey<String>('tailscale-switch')));
    expect(s.value, isFalse);
    expect(s.onChanged, isNull);
  });

  testWidgets('polls until the NAS has applied it', (WidgetTester t) async {
    int calls = 0;
    await t.pumpWidget(host(TailscaleScreen(
      load: () async => ++calls == 1 ? st(on: true, pending: 'off') : st(on: false, changedBy: 'matty', changedAt: 1793094961),
      set: (bool on) async => st(),
      pollEvery: const Duration(seconds: 5),
    )));
    await t.pumpAndSettle();
    expect(find.text('Switching… the NAS applies it within a minute'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Off: nothing at home is reachable over Tailscale'), findsOneWidget);
    expect(find.textContaining('by matty'), findsOneWidget);
  });

  testWidgets('says so when the NAS job is not reporting', (WidgetTester t) async {
    await t.pumpWidget(host(TailscaleScreen(load: () async => st(stale: true), set: (bool on) async => st())));
    await t.pumpAndSettle();
    expect(find.text("The NAS hasn't reported the state for a few minutes"), findsOneWidget);
  });

  testWidgets('Czech', (WidgetTester t) async {
    lang.value = 'cs';
    await t.pumpWidget(host(TailscaleScreen(load: () async => st(on: false), set: (bool on) async => st())));
    await t.pumpAndSettle();
    expect(find.text('Vypnuto: domácí síť přes Tailscale dostupná není'), findsOneWidget);
    expect(find.text('Vzdálený přístup (Tailscale)'), findsOneWidget);
  });

  testWidgets('a failed load shows an error', (WidgetTester t) async {
    await t.pumpWidget(host(TailscaleScreen(load: () async => throw Exception('x'), set: (bool on) async => st())));
    await t.pumpAndSettle();
    expect(find.text("Couldn't reach the NAS"), findsOneWidget);
  });
}
