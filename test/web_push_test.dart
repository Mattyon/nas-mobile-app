// The "Notifications on this device" dialog of the web build, driven by a fake browser.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/web_push.dart';
import 'package:nas_app/web_push_stub.dart' as stub;

class FakePush implements WebPush {
  FakePush(this.s);
  PushState s;
  final List<String> calls = <String>[];
  Object? failWith;

  @override
  Future<PushState> state() async => s;
  @override
  Future<PushState> enable(String token, String lang) async {
    calls.add('enable $lang');
    if (failWith != null) throw failWith!;
    return s = PushState.on;
  }

  @override
  Future<PushState> disable(String token) async {
    calls.add('disable');
    return s = PushState.off;
  }
}

Future<void> open(WidgetTester t, FakePush p) async {
  webPush = p;
  await t.pumpWidget(const MaterialApp(home: Scaffold(body: WebPushDialog())));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => lang.value = 'en');

  test('state strings from push.js', () {
    expect(pushStateFrom('on'), PushState.on);
    expect(pushStateFrom('off'), PushState.off);
    expect(pushStateFrom('denied'), PushState.denied);
    expect(pushStateFrom('needs-home-screen'), PushState.needsHomeScreen);
    expect(pushStateFrom('anything else'), PushState.unsupported);
  });

  testWidgets('off: turning on subscribes in the app language', (WidgetTester t) async {
    lang.value = 'cs';
    final FakePush p = FakePush(PushState.off);
    await open(t, p);
    await t.tap(find.text(tr('webPushTurnOn')));
    await t.pumpAndSettle();
    expect(p.calls, <String>['enable cs']);
    expect(find.text(tr('webPushOn')), findsOneWidget);
    expect(find.text(tr('webPushTurnOff')), findsOneWidget);
  });

  testWidgets('on: turning off unsubscribes', (WidgetTester t) async {
    final FakePush p = FakePush(PushState.on);
    await open(t, p);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(p.calls, <String>['disable']);
    expect(find.text(tr('webPushOff')), findsOneWidget);
  });

  testWidgets('iPhone outside the home-screen app: explains, no button', (WidgetTester t) async {
    await open(t, FakePush(PushState.needsHomeScreen));
    expect(find.textContaining('Add to Home Screen'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('blocked or unsupported: explains, no button', (WidgetTester t) async {
    await open(t, FakePush(PushState.denied));
    expect(find.textContaining('blocked'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await open(t, FakePush(PushState.unsupported));
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('an error is shown, not swallowed', (WidgetTester t) async {
    final FakePush p = FakePush(PushState.off)..failWith = Exception('HTTP 500');
    await open(t, p);
    await t.tap(find.text('Turn on'));
    await t.pumpAndSettle();
    expect(find.textContaining('HTTP 500'), findsOneWidget);
  });

  test('outside a browser it is unsupported (Android uses ntfy)', () async {
    expect(await stub.create().state(), PushState.unsupported);
  });

  test('every new key exists in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      for (final String k in <String>['webPush', 'webPushOn', 'webPushOff', 'webPushTurnOn',
          'webPushTurnOff', 'webPushDenied', 'webPushHomeScreen', 'webPushUnsupported',
          'webPushError', 'close']) {
        expect(tr(k), isNot(k), reason: '$l $k');
      }
    }
  });
}
