import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'tailscale_screen.dart';

// The ☰ menu, grouped (owner, 2026-10-27: "it contains too many items at once. Let's just
// group these within a few pages"). The main menu holds a few entries; a group opens a page
// with its items. Only what the role may use is shown, and a group with a single visible
// item is shown as that item, never as a one-item page.
//
//   AI assistant (superadmin)
//   Server ›     health check, Uptime Kuma, speed test, media sessions      (admin)
//   Downloads ›  speed limits (admin), check for new episodes, trash (admin)
//   Home ›       remote access / Tailscale (superadmin, a switch right on the page),
//                smart sockets (admin), cameras (superadmin)
//   Users (admin)
//   Settings & help ›  dark/light mode, Jellyfin URL, notifications on this device (web), help
//   Log out
//
// The ids are the actions HomeShell's _menuAction carries out.

class MenuGroup {
  const MenuGroup(this.id, this.icon, this.titleKey, this.items);
  final String id;
  final IconData icon;
  final String titleKey;
  final List<String> items;
}

/// A main-menu entry: one action, or a group of them on its own page.
class MenuNode {
  const MenuNode.action(String this.action) : group = null;
  const MenuNode.group(MenuGroup this.group) : action = null;
  final String? action;
  final MenuGroup? group;

  @override
  String toString() => action ?? '${group!.id}:${group!.items.join(',')}';
}

bool menuItemVisible(String id, {required bool admin, required bool superadmin, required bool web}) {
  switch (id) {
    case 'ai':
    case 'tailscale':
    case 'camera':
      return superadmin;
    case 'health':
    case 'kuma':
    case 'speedtest':
    case 'sessions':
    case 'speed':
    case 'trash':
    case 'tapo':
    case 'users':
      return admin;
    case 'webpush':
      return web;
    default: // neweps, theme, jellyfin, help, logout
      return true;
  }
}

const List<Object> _layout = <Object>[
  'ai',
  MenuGroup('server', Icons.dns_outlined, 'menuServer', <String>['health', 'kuma', 'speedtest', 'sessions']),
  MenuGroup('downloads', Icons.download_outlined, 'downloads', <String>['speed', 'neweps', 'trash']),
  MenuGroup('home', Icons.home_outlined, 'menuHome', <String>['tailscale', 'tapo', 'camera']),
  'users',
  MenuGroup('settings', Icons.settings_outlined, 'menuSettings', <String>['theme', 'jellyfin', 'webpush', 'help']),
  'logout',
];

/// The main menu for a role.
List<MenuNode> buildAppMenu({required bool admin, required bool superadmin, bool web = kIsWeb}) {
  bool visible(String id) => menuItemVisible(id, admin: admin, superadmin: superadmin, web: web);
  final List<MenuNode> out = <MenuNode>[];
  for (final Object entry in _layout) {
    if (entry is String) {
      if (visible(entry)) out.add(MenuNode.action(entry));
    } else if (entry is MenuGroup) {
      final List<String> items = entry.items.where(visible).toList();
      if (items.length == 1) {
        out.add(MenuNode.action(items.single));
      } else if (items.isNotEmpty) {
        out.add(MenuNode.group(MenuGroup(entry.id, entry.icon, entry.titleKey, items)));
      }
    }
  }
  return out;
}

String menuLabel(String id, {bool dark = false}) {
  switch (id) {
    case 'ai': return tr('aiChats');
    case 'health': return tr('healthCheck');
    case 'kuma': return 'Uptime Kuma'; // product names stay untranslated
    case 'speedtest': return tr('speedtest');
    case 'sessions': return tr('mediaSessions');
    case 'speed': return tr('speedLimits');
    case 'neweps': return tr('checkNewEps');
    case 'trash': return tr('trash');
    case 'tailscale': return tr('tailscaleRemoteAccess');
    case 'tapo': return tr('tapoDevices');
    case 'camera': return tr('cameraFeed');
    case 'users': return tr('userManagement');
    case 'theme': return dark ? tr('lightMode') : tr('darkMode');
    case 'jellyfin': return 'Jellyfin URL';
    case 'webpush': return tr('webPush');
    case 'help': return tr('helpConnect');
    case 'logout': return tr('logout');
  }
  return id;
}

IconData menuIcon(String id, {bool dark = false}) {
  switch (id) {
    case 'ai': return Icons.smart_toy_outlined;
    case 'health': return Icons.health_and_safety_outlined;
    case 'kuma': return Icons.monitor_heart_outlined;
    case 'speedtest': return Icons.network_check;
    case 'sessions': return Icons.cast_connected;
    case 'speed': return Icons.speed;
    case 'neweps': return Icons.tv;
    case 'trash': return Icons.delete_outline;
    case 'tailscale': return Icons.vpn_lock_outlined;
    case 'tapo': return Icons.power_outlined;
    case 'camera': return Icons.videocam_outlined;
    case 'users': return Icons.people;
    case 'theme': return dark ? Icons.light_mode : Icons.dark_mode;
    case 'jellyfin': return Icons.play_circle_outline;
    case 'webpush': return Icons.notifications_active_outlined;
    case 'help': return Icons.help_outline;
    case 'logout': return Icons.logout;
  }
  return Icons.circle_outlined;
}

/// One group's page. Tapping an item runs [onSelect] with its id; the Tailscale item is a
/// switch right here, not a link.
class MenuGroupPage extends StatelessWidget {
  const MenuGroupPage({super.key, required this.group, required this.onSelect, required this.themeMode,
      this.tailscale});

  final MenuGroup group;
  final Future<void> Function(String id) onSelect;
  final ValueListenable<ThemeMode> themeMode;
  /// Injectable for tests; defaults to the live switch.
  final Widget? tailscale;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: lang,
      builder: (BuildContext _, String __, Widget? ___) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (BuildContext ctx, ThemeMode mode, Widget? ____) {
          final bool dark = mode == ThemeMode.dark;
          return Scaffold(
            appBar: AppBar(title: Text(tr(group.titleKey))),
            body: ListView(
              children: <Widget>[
                for (final String id in group.items)
                  if (id == 'tailscale')
                    Card(margin: const EdgeInsets.all(8), child: tailscale ?? const TailscaleSwitchTile())
                  else
                    ListTile(
                      key: ValueKey<String>('menu-$id'),
                      leading: Icon(menuIcon(id, dark: dark)),
                      title: Text(menuLabel(id, dark: dark)),
                      onTap: () => onSelect(id),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
