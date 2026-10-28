import 'time_zone_stub.dart' if (dart.library.js_interop) 'time_zone_web.dart' as impl;

// Where the phone is, for quiet hours on the reader's own clock (owner, 2026-10-28: "it must
// respect their current timezone"). The zone name ("Europe/Prague") is sent whenever the app
// opens; the clock's UTC offset also by the background service when it changes, which
// covers a trip abroad on which the app is never opened.

/// The device's time zone name, or null when it cannot be told.
Future<String?> deviceTimeZone() => impl.deviceTimeZone();

/// The device clock's offset from UTC, in minutes.
int utcOffsetMinutes([DateTime? now]) => (now ?? DateTime.now()).timeZoneOffset.inMinutes;
