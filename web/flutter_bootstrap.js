{{flutter_js}}
{{flutter_build_config}}

// No Flutter service worker. Its default one only unregisters itself, but it would
// claim the /app/ scope that web/push-sw.js needs for Web Push.
_flutter.loader.load();
