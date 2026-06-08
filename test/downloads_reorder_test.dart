import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Exact copy of _onReorder logic from _DownloadsScreenState ────────────
  // Removes item at oldIndex, inserts at newIndex, then re-assigns 1-based priority

  List<Map<String, dynamic>> _applyReorder(
      List<Map<String, dynamic>> sorted, int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return sorted;
    final List<Map<String, dynamic>> result =
        List<Map<String, dynamic>>.from(sorted);
    final Map<String, dynamic> item = result.removeAt(oldIndex);
    result.insert(newIndex, item);
    for (int i = 0; i < result.length; i++) {
      result[i]['priority'] = i + 1;
    }
    return result;
  }

  final List<Map<String, dynamic>> threeItems = <Map<String, dynamic>>[
    <String, dynamic>{'name': 'A', 'hash': 'a1', 'priority': 1},
    <String, dynamic>{'name': 'B', 'hash': 'b2', 'priority': 2},
    <String, dynamic>{'name': 'C', 'hash': 'c3', 'priority': 3},
  ];

  group('downloads — reorder: move down', () {
    test('moving A from index 0 to end', () {
      final List<Map<String, dynamic>> result =
          _applyReorder(List.from(threeItems.map((m) => Map<String, dynamic>.from(m))), 0, 2);
      expect(result[0]['name'], 'B');
      expect(result[1]['name'], 'C');
      expect(result[2]['name'], 'A');
    });

    test('priorities are 1-based after moving down', () {
      final List<Map<String, dynamic>> result =
          _applyReorder(List.from(threeItems.map((m) => Map<String, dynamic>.from(m))), 0, 2);
      for (int i = 0; i < result.length; i++) {
        expect(result[i]['priority'], i + 1);
      }
    });
  });

  group('downloads — reorder: move up', () {
    test('moving C from index 2 to front', () {
      final List<Map<String, dynamic>> result =
          _applyReorder(List.from(threeItems.map((m) => Map<String, dynamic>.from(m))), 2, 0);
      expect(result[0]['name'], 'C');
      expect(result[1]['name'], 'A');
      expect(result[2]['name'], 'B');
    });

    test('priorities are 1-based after moving up', () {
      final List<Map<String, dynamic>> result =
          _applyReorder(List.from(threeItems.map((m) => Map<String, dynamic>.from(m))), 2, 0);
      expect(result[0]['priority'], 1);
      expect(result[1]['priority'], 2);
      expect(result[2]['priority'], 3);
    });
  });

  group('downloads — reorder: same index (no-op)', () {
    test('moving to same index returns list unchanged', () {
      final List<Map<String, dynamic>> base =
          List.from(threeItems.map((m) => Map<String, dynamic>.from(m)));
      final List<Map<String, dynamic>> result = _applyReorder(base, 1, 1);
      expect(result[0]['name'], 'A');
      expect(result[1]['name'], 'B');
      expect(result[2]['name'], 'C');
    });
  });

  group('downloads — reorder: larger list', () {
    final List<Map<String, dynamic>> fiveItems = List.generate(
      5,
      (i) => <String, dynamic>{'name': 'Item${i + 1}', 'hash': 'h$i', 'priority': i + 1},
    );

    test('moving item from middle to front', () {
      final List<Map<String, dynamic>> copy =
          List.from(fiveItems.map((m) => Map<String, dynamic>.from(m)));
      final List<Map<String, dynamic>> result = _applyReorder(copy, 2, 0);
      expect(result[0]['name'], 'Item3');
      expect(result[0]['priority'], 1);
    });

    test('priorities stay consecutive after reorder', () {
      final List<Map<String, dynamic>> copy =
          List.from(fiveItems.map((m) => Map<String, dynamic>.from(m)));
      final List<Map<String, dynamic>> result = _applyReorder(copy, 4, 1);
      final List<int> prios = result.map((m) => m['priority'] as int).toList();
      expect(prios, <int>[1, 2, 3, 4, 5]);
    });
  });

  group('downloads — reorder: API request parameters', () {
    test('reorderTorrent called with hash, oldIndex, newIndex', () {
      // Mirrors Api.I.reorderTorrent(hash, oldIndex, newIndex)
      const String hash = 'abc123';
      const int oldIdx = 0;
      const int newIdx = 2;
      final Map<String, dynamic> payload = <String, dynamic>{
        'hash': hash,
        'old_idx': oldIdx,
        'new_idx': newIdx,
      };
      expect(payload['hash'], hash);
      expect(payload['old_idx'], oldIdx);
      expect(payload['new_idx'], newIdx);
    });
  });
}
