// Tapping a notification opens what it is about (owner, 2026-10-28: "I want notifications
// to be clickable, so e.g. new version available opens store"). The gateway stores each
// notification's `event` (a notify_rules key) and, where there is one, the `kind` and
// `item_id` it is about. The target travels as the system notification's payload, and the
// bell list uses the same one.
//
//   tab:0 / tab:1 / tab:2   Search / Downloads / Library
//   movie:<id> / tv:<id>    that title's page ("ready"), by its Radarr/Sonarr id
//   store                   the app's Play Store listing
//   chat:<id>               that AI chat
//   kuma                    Uptime Kuma
//   health                  the health check (admins)

const String kStoreUrl = 'https://play.google.com/store/apps/details?id=mattyzem.nas';

/// Where tapping notification [n] leads, or null when it only opens the app.
String? notificationTarget(Map<String, dynamic> n) {
  final String event = n['event']?.toString() ?? '';
  switch (event) {
    case '':
      return null;
    case 'app.release':
      return 'store';
    case 'chat.reply':
      final Object? id = n['item_id'];
      return id == null ? null : 'chat:$id';
    case 'monitor':
      return 'kuma';
    case 'movie.ready':
    case 'tv.ready':
    case 'tv.first_ready':
      // the title itself, when the notification says which (owner, 2026-11-23)
      final Object? item = n['item_id'];
      final String kind = n['kind']?.toString() ?? '';
      if (item != null && (kind == 'movie' || kind == 'tv')) return '$kind:$item';
      return 'tab:2';
    case 'tv.new_episodes':
    case 'tv.premiere':
    case 'tv.still_missing':
      return 'tab:2';
    case 'tv.pack_auto':
    case 'download.still_stalled':
    case 'download.stalled':
    case 'download.failed':
      return 'tab:1';
    case 'download.grab_failed':
    case 'download.nothing_found':
    case 'czech.unavailable':
    case 'czech.wrong_language':
      return 'tab:0'; // nothing came down: search again
  }
  return 'health'; // everything else is a server alert for the admin
}
