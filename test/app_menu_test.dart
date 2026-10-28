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
      'house:tailscale,tapo,camera,recordings',
      'users',
      'settings:theme,jellyfin,help',
      'logout',
    ]);
  });

  test('admin: no AI; House has only smart sockets, so it is a plain item', () {
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
          'tailscale', 'tapo', 'camera', 'recordings', 'users', 'theme', 'jellyfin', 'webpush', 'help', 'logout']) {
        expect(menuLabel(id), isNot(equals(id)), reason: '$l $id');
        expect(menuIcon(id), isNot(Icons.circle_outlined), reason: id);
      }
      for (final String k in <String>['menuServer', 'menuHouse', 'menuSettings', 'downloads']) {
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

  testWidgets('House: the Tailscale switch is on the page itself', (WidgetTester t) async {
    final MenuGroup g = buildAppMenu(admin: true, superadmin: true, web: false)
        .firstWhere((MenuNode n) => n.group?.id == 'house').group!;
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

  test('only House opens a page; the other groups are submenus', () {
    final List<MenuGroup> groups = buildAppMenu(admin: true, superadmin: true, web: false)
        .map((MenuNode n) => n.group).whereType<MenuGroup>().toList();
    expect(<String>[for (final MenuGroup g in groups) g.value],
        <String>['sub:server', 'sub:downloads', 'page:house', 'sub:settings']);
    expect(menuGroupFor('sub:server', admin: true, superadmin: true, web: false)!.items.first, 'health');
    expect(menuGroupFor('sub:server', admin: false, superadmin: false, web: false), isNull);
  });

  Future<void> open(WidgetTester t, List<PopupMenuEntry<String>> items) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (BuildContext c) =>
        TextButton(onPressed: () => showMenu<String>(context: c, position: RelativeRect.fill, items: items),
            child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  bool chevron(String key) => find.descendant(of: find.byKey(ValueKey<String>(key)),
      matching: find.byIcon(Icons.chevron_right)).evaluate().isNotEmpty;

  testWidgets('main menu: › on submenus, none on House', (WidgetTester t) async {
    await open(t, mainMenuEntries(buildAppMenu(admin: true, superadmin: true, web: false)));
    expect(chevron('menu-sub:server'), isTrue);
    expect(chevron('menu-sub:downloads'), isTrue);
    expect(chevron('menu-sub:settings'), isTrue);
    expect(chevron('menu-page:house'), isFalse);
    expect(find.text('House'), findsOneWidget);
    expect(find.text('AI chats'), findsOneWidget);
  });

  testWidgets('a submenu: its items and a way back to the main menu', (WidgetTester t) async {
    final List<PopupMenuEntry<String>> sub = submenuEntries(
        menuGroupFor('sub:downloads', admin: true, superadmin: true, web: false)!);
    expect(<String?>[for (final PopupMenuEntry<String> e in sub) if (e is PopupMenuItem<String>) e.value],
        <String?>['back', 'speed', 'neweps', 'trash']);
    await open(t, sub);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('menu-back')), matching: find.text('Downloads')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('menu-back')), matching: find.byIcon(Icons.chevron_left)),
        findsOneWidget);
  });
}
