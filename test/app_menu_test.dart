import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/app_menu.dart';
import 'package:nas_app/i18n.dart';

// The grouped ☰ menu (owner, 2026-10-27): a few entries, groups on their own pages, only
// what the role may use, and never a page with a single item.

List<String> menu({bool admin = false, bool superadmin = false, bool web = false}) =>
    buildAppMenu(admin: admin, superadmin: superadmin, web: web).map((MenuNode n) => n.toString()).toList();

void main() {
  setUp(() => lang.value = 'en');

  test('superadmin (and admin): the full layout', () {
    expect(menu(admin: true, superadmin: true), <String>[
      'ai',
      'server:health,kuma,speedtest,sessions',
      'downloads:speed,neweps,trash',
      'home:tailscale,tapo,camera',
      'users',
      'settings:theme,jellyfin,help',
      'logout',
    ]);
  });

  test('admin: no AI; Home has only smart sockets, so it is a plain item', () {
    expect(menu(admin: true), <String>[
      'server:health,kuma,speedtest,sessions',
      'downloads:speed,neweps,trash',
      'tapo',
      'users',
      'settings:theme,jellyfin,help',
      'logout',
    ]);
  });

  test('a regular user: check for new episodes, settings, log out', () {
    expect(menu(), <String>['neweps', 'settings:theme,jellyfin,help', 'logout']);
  });

  test('web build: notifications on this device in settings', () {
    expect(menu(web: true), contains('settings:theme,jellyfin,webpush,help'));
  });

  test('no Kill app anywhere', () {
    expect(menu(admin: true, superadmin: true, web: true).join(' '), isNot(contains('kill')));
  });

  test('every item has a label and an icon, in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      for (final String id in <String>['ai', 'health', 'kuma', 'speedtest', 'sessions', 'speed', 'neweps', 'trash',
          'tailscale', 'tapo', 'camera', 'users', 'theme', 'jellyfin', 'webpush', 'help', 'logout']) {
        expect(menuLabel(id), isNot(equals(id)), reason: '$l $id');
        expect(menuIcon(id), isNot(Icons.circle_outlined), reason: id);
      }
      for (final String k in <String>['menuServer', 'menuHome', 'menuSettings', 'downloads']) {
        expect(tr(k), isNot(equals(k)), reason: '$l $k');
      }
    }
  });

  testWidgets('a group page lists its items and reports the one tapped', (WidgetTester t) async {
    final List<String> picked = <String>[];
    final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.light);
    final MenuGroup g = buildAppMenu(admin: true, superadmin: true, web: false)
        .firstWhere((MenuNode n) => n.group?.id == 'server').group!;
    await t.pumpWidget(MaterialApp(home: MenuGroupPage(
        group: g, themeMode: mode, onSelect: (String id) async => picked.add(id))));
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Health Check'), findsOneWidget);
    expect(find.text('Uptime Kuma'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('menu-speedtest')));
    expect(picked, <String>['speedtest']);
  });

  testWidgets('Home: the Tailscale switch is on the page itself', (WidgetTester t) async {
    final MenuGroup g = buildAppMenu(admin: true, superadmin: true, web: false)
        .firstWhere((MenuNode n) => n.group?.id == 'home').group!;
    await t.pumpWidget(MaterialApp(home: MenuGroupPage(
        group: g, themeMode: ValueNotifier<ThemeMode>(ThemeMode.light), onSelect: (String id) async {},
        tailscale: const Text('TAILSCALE-SWITCH'))));
    expect(find.text('TAILSCALE-SWITCH'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('menu-tailscale')), findsNothing);
    expect(find.text('Smart Sockets'), findsOneWidget);
  });

  testWidgets('settings: the theme item follows the mode', (WidgetTester t) async {
    final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.light);
    final MenuGroup g = buildAppMenu(admin: false, superadmin: false, web: false)
        .firstWhere((MenuNode n) => n.group?.id == 'settings').group!;
    await t.pumpWidget(MaterialApp(home: MenuGroupPage(group: g, themeMode: mode, onSelect: (String id) async {})));
    expect(find.text(tr('darkMode')), findsOneWidget);
    mode.value = ThemeMode.dark;
    await t.pump();
    expect(find.text(tr('lightMode')), findsOneWidget);
  });
}
