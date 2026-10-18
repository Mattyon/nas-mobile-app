import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/main.dart' show channelFor;
import 'package:nas_app/notification_settings.dart';

// The mute switches (#43) and the quiet-hours channel (#42) from the owner's
// notification review. The gateway owns the list of groups; the screen shows one switch
// per group (on = notified) and sends back the ids that are off.

Map<String, dynamic> _prefs({List<String> muted = const <String>[]}) => <String, dynamic>{
      'groups': <Map<String, dynamic>>[
        for (final List<String> g in const <List<String>>[
          <String>['ready', 'Ready to watch', 'Připraveno ke sledování'],
          <String>['chat', 'AI chat replies', 'Odpovědi AI chatu'],
        ])
          <String, dynamic>{'id': g[0], 'label': g[1], 'label_cs': g[2], 'muted': muted.contains(g[0])},
      ],
    };

Widget _app(NotificationSettingsPage page) => MaterialApp(home: page);

bool _isOn(WidgetTester t, String id) =>
    t.widget<SwitchListTile>(find.byKey(ValueKey<String>('notif-$id'))).value;

void main() {
  setUp(() => lang.value = 'en');

  testWidgets('one switch per group, on unless muted', (WidgetTester t) async {
    await t.pumpWidget(_app(NotificationSettingsPage(
        load: () async => _prefs(muted: <String>['chat']),
        save: (_) async => _prefs())));
    await t.pumpAndSettle();
    expect(find.text('Ready to watch'), findsOneWidget);
    expect(_isOn(t, 'ready'), isTrue);
    expect(_isOn(t, 'chat'), isFalse);
  });

  testWidgets('labels follow the app language', (WidgetTester t) async {
    lang.value = 'cs';
    await t.pumpWidget(_app(NotificationSettingsPage(
        load: () async => _prefs(), save: (_) async => _prefs())));
    await t.pumpAndSettle();
    expect(find.text('Připraveno ke sledování'), findsOneWidget);
  });

  testWidgets('turning one off saves exactly the muted ids', (WidgetTester t) async {
    List<String>? sent;
    await t.pumpWidget(_app(NotificationSettingsPage(
        load: () async => _prefs(muted: <String>['chat']),
        save: (List<String> m) async {
          sent = m;
          return _prefs(muted: m);
        })));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('notif-ready')));
    await t.pumpAndSettle();
    expect(sent, unorderedEquals(<String>['ready', 'chat']));
    expect(_isOn(t, 'ready'), isFalse);
  });

  testWidgets('a failed save puts the switch back', (WidgetTester t) async {
    await t.pumpWidget(_app(NotificationSettingsPage(
        load: () async => _prefs(),
        save: (_) async => throw Exception('offline'))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('notif-ready')));
    await t.pumpAndSettle();
    expect(_isOn(t, 'ready'), isTrue);
    expect(find.text(tr('notificationSettingsError')), findsOneWidget);
  });

  testWidgets('a failed load says so', (WidgetTester t) async {
    await t.pumpWidget(_app(NotificationSettingsPage(
        load: () async => throw Exception('offline'), save: (_) async => _prefs())));
    await t.pumpAndSettle();
    expect(find.text(tr('notificationSettingsError')), findsOneWidget);
  });

  testWidgets('quiet hours are explained', (WidgetTester t) async {
    await t.pumpWidget(_app(NotificationSettingsPage(
        load: () async => _prefs(), save: (_) async => _prefs())));
    await t.pumpAndSettle();
    expect(find.text(tr('quietHours')), findsOneWidget);
  });

  group('channel', () {
    test('a silent notification goes on the quiet channel', () {
      expect(channelFor(<String, dynamic>{'silent': true}).id, 'nas_alerts_quiet');
    });
    test('anything else rings', () {
      expect(channelFor(<String, dynamic>{'silent': false}).id, 'nas_alerts');
      expect(channelFor(<String, dynamic>{}).id, 'nas_alerts');
    });
  });

  group('i18n', () {
    for (final String key in <String>[
      'notificationSettings', 'notificationSettingsHint', 'notificationSettingsError',
      'quietHours', 'quietHoursHint',
    ]) {
      for (final String l in <String>['en', 'cs']) {
        test('$l "$key"', () {
          lang.value = l;
          expect(tr(key), isNot(equals(key)));
        });
      }
    }
  });
}
