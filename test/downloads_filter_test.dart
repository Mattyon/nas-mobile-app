import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Exact logic from _DownloadsScreenState._filtered() ───────────────────

  const Set<String> _activeStates = <String>{
    'downloading', 'forcedDL', 'metaDL', 'stalledDL', 'checkingDL', 'allocating',
  };
  const Set<String> _failedStates = <String>{'error', 'missingFiles'};

  int _group(String s) {
    if (_activeStates.contains(s)) return 0;
    if (s == 'queuedDL') return 1;
    if (_failedStates.contains(s)) return 3;
    return 2;
  }

  List<Map<String, dynamic>> _filtered(
      List<dynamic> items, bool active, String query) {
    final String ql = query.trim().toLowerCase();
    final List<Map<String, dynamic>> result = items
        .map((dynamic e) => e as Map<String, dynamic>)
        .where((Map<String, dynamic> t) {
          final int g = _group(t['state']?.toString() ?? '');
          if (active ? g > 1 : g <= 1) return false;
          if (ql.isEmpty) return true;
          return (t['name']?.toString() ?? '').toLowerCase().contains(ql);
        })
        .toList();

    result.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int ga = _group(a['state']?.toString() ?? '');
      final int gb = _group(b['state']?.toString() ?? '');
      if (ga != gb) return ga.compareTo(gb);
      if (ga == 0) {
        final int pa = (a['priority'] as num?)?.toInt() ?? 0;
        final int pb = (b['priority'] as num?)?.toInt() ?? 0;
        final int ea = pa == 0 ? 999999 : pa;
        final int eb = pb == 0 ? 999999 : pb;
        return ea.compareTo(eb);
      }
      return 0;
    });
    return result;
  }

  // ── Fixture data ──────────────────────────────────────────────────────────

  final List<Map<String, dynamic>> items = <Map<String, dynamic>>[
    <String, dynamic>{'name': 'Alpha', 'state': 'downloading', 'priority': 1},
    <String, dynamic>{'name': 'Beta', 'state': 'queuedDL', 'priority': 2},
    <String, dynamic>{'name': 'Gamma', 'state': 'stalledDL', 'priority': 3},
    <String, dynamic>{'name': 'Delta', 'state': 'uploading', 'priority': 0},
    <String, dynamic>{'name': 'Epsilon', 'state': 'error', 'priority': 0},
    <String, dynamic>{'name': 'Zeta', 'state': 'stoppedUP', 'priority': 0},
    <String, dynamic>{'name': 'Eta', 'state': 'missingFiles', 'priority': 0},
    <String, dynamic>{'name': 'Theta', 'state': 'forcedDL', 'priority': 4},
  ];

  // ── Active tab content ────────────────────────────────────────────────────

  group('downloads — active tab includes correct items', () {
    late List<Map<String, dynamic>> active;
    setUp(() => active = _filtered(items, true, ''));

    test('includes downloading', () =>
        expect(active.any((t) => t['name'] == 'Alpha'), isTrue));
    test('includes queuedDL', () =>
        expect(active.any((t) => t['name'] == 'Beta'), isTrue));
    test('includes stalledDL', () =>
        expect(active.any((t) => t['name'] == 'Gamma'), isTrue));
    test('includes forcedDL', () =>
        expect(active.any((t) => t['name'] == 'Theta'), isTrue));
    test('active tab has 4 items (downloading+stalledDL+forcedDL+queuedDL)', () =>
        expect(active.length, 4));
  });

  group('downloads — active tab excludes finished and failed', () {
    late List<Map<String, dynamic>> active;
    setUp(() => active = _filtered(items, true, ''));

    test('excludes uploading', () =>
        expect(active.any((t) => t['name'] == 'Delta'), isFalse));
    test('excludes error', () =>
        expect(active.any((t) => t['name'] == 'Epsilon'), isFalse));
    test('excludes stoppedUP', () =>
        expect(active.any((t) => t['name'] == 'Zeta'), isFalse));
    test('excludes missingFiles', () =>
        expect(active.any((t) => t['name'] == 'Eta'), isFalse));
  });

  // ── Finished tab content ──────────────────────────────────────────────────

  group('downloads — finished tab includes correct items', () {
    late List<Map<String, dynamic>> finished;
    setUp(() => finished = _filtered(items, false, ''));

    test('includes uploading', () =>
        expect(finished.any((t) => t['name'] == 'Delta'), isTrue));
    test('includes error', () =>
        expect(finished.any((t) => t['name'] == 'Epsilon'), isTrue));
    test('includes stoppedUP', () =>
        expect(finished.any((t) => t['name'] == 'Zeta'), isTrue));
    test('includes missingFiles', () =>
        expect(finished.any((t) => t['name'] == 'Eta'), isTrue));
    test('finished tab has 4 items', () =>
        expect(finished.length, 4));
  });

  group('downloads — finished tab excludes active items', () {
    late List<Map<String, dynamic>> finished;
    setUp(() => finished = _filtered(items, false, ''));

    test('excludes downloading', () =>
        expect(finished.any((t) => t['name'] == 'Alpha'), isFalse));
    test('excludes queuedDL', () =>
        expect(finished.any((t) => t['name'] == 'Beta'), isFalse));
  });

  // ── Active tab sort order ─────────────────────────────────────────────────

  group('downloads — active tab sort: group 0 before group 1', () {
    test('downloading comes before queuedDL in active list', () {
      final List<Map<String, dynamic>> active = _filtered(items, true, '');
      final int dlIdx = active.indexWhere((t) => t['state'] == 'downloading');
      final int qIdx = active.indexWhere((t) => t['state'] == 'queuedDL');
      expect(dlIdx, lessThan(qIdx));
    });
  });

  group('downloads — active tab sort: priority within group 0', () {
    final List<Map<String, dynamic>> prioItems = <Map<String, dynamic>>[
      <String, dynamic>{'name': 'P5', 'state': 'downloading', 'priority': 5},
      <String, dynamic>{'name': 'P1', 'state': 'downloading', 'priority': 1},
      <String, dynamic>{'name': 'P3', 'state': 'downloading', 'priority': 3},
      <String, dynamic>{'name': 'P0', 'state': 'downloading', 'priority': 0},
    ];

    test('lower priority number sorts first', () {
      final List<Map<String, dynamic>> active = _filtered(prioItems, true, '');
      expect(active[0]['name'], 'P1');
      expect(active[1]['name'], 'P3');
      expect(active[2]['name'], 'P5');
    });

    test('priority 0 sorts to end (treated as 999999)', () {
      final List<Map<String, dynamic>> active = _filtered(prioItems, true, '');
      expect(active.last['name'], 'P0');
    });
  });

  // ── Finished tab sort: failed after finished ──────────────────────────────

  group('downloads — finished tab sort: errors after finished', () {
    test('group 2 (uploading) sorts before group 3 (error)', () {
      final List<Map<String, dynamic>> finished = _filtered(items, false, '');
      final int uploadIdx = finished.indexWhere((t) => t['state'] == 'uploading');
      final int errorIdx = finished.indexWhere((t) => t['state'] == 'error');
      expect(uploadIdx, lessThan(errorIdx));
    });
  });

  // ── Search filter ─────────────────────────────────────────────────────────

  group('downloads — search filter', () {
    test('empty query returns all active tab items', () {
      expect(_filtered(items, true, '').length, 4);
    });

    test('exact name match', () {
      final List<Map<String, dynamic>> result = _filtered(items, true, 'Alpha');
      expect(result.length, 1);
      expect(result[0]['name'], 'Alpha');
    });

    test('case-insensitive filter', () {
      expect(_filtered(items, true, 'alpha').length, 1);
      expect(_filtered(items, true, 'ALPHA').length, 1);
    });

    test('partial match works', () {
      // 'al' matches 'Alpha'
      expect(_filtered(items, true, 'al').length, 1);
    });

    test('no-match returns empty list', () {
      expect(_filtered(items, true, 'zznotfound'), isEmpty);
    });

    test('whitespace-padded query is trimmed', () {
      expect(_filtered(items, true, '  Alpha  ').length, 1);
    });
  });
}
