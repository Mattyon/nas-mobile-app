// Which notifications the phone should not show (owner, 2026-10-27: "I should not get a
// notification if I am already on the newest version - the nas app should check and drop
// it"). The gateway already skips users whose phones report the version (app_release.py);
// this catches the rest, e.g. a second phone that updated before telling the gateway.

/// "1.1.8" -> [1, 1, 8]; null for "dev" or anything unparseable.
List<int>? parseVersion(String v) {
  final List<String> parts = v.split('+').first.split('.');
  final List<int> out = <int>[];
  for (final String p in parts) {
    final int? n = int.tryParse(p);
    if (n == null) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

int compareVersions(List<int> a, List<int> b) {
  for (int i = 0; i < a.length || i < b.length; i++) {
    final int x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// A "new app version" notice for a version this app already is (or is newer than).
bool alreadyInstalled(Map<String, dynamic> n, String appVersion) {
  if (n['event'] != 'app.release') return false;
  final List<int>? mine = parseVersion(appVersion);
  if (mine == null) return false;
  final RegExpMatch? m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch('${n['body'] ?? ''}');
  final List<int>? announced = m == null ? null : parseVersion(m.group(1)!);
  return announced != null && compareVersions(mine, announced) >= 0;
}
