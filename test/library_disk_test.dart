import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Exact copy of _freeStr(double gb) from _LibraryScreenState ───────────
  String _freeStr(double gb) {
    if (gb >= 1000) return '${(gb / 1000).toStringAsFixed(2)} TB';
    if (gb >= 1) return '${gb.toStringAsFixed(0)} GB';
    return '${(gb * 1000).toStringAsFixed(0)} MB';
  }

  // ── Mirrors _diskColor() threshold logic (as color name string) ───────────
  // pct > 85 → red; > 80 → orange; > 70 → yellow; else → green
  String _diskColorName(double pct) {
    if (pct > 85) return 'red';
    if (pct > 80) return 'orange';
    if (pct > 70) return 'yellow';
    return 'green';
  }

  // ── _freeStr() — GB display ───────────────────────────────────────────────

  group('library — _freeStr: GB range', () {
    test('1.0 GB → "1 GB"', () => expect(_freeStr(1.0), '1 GB'));
    test('10.0 GB → "10 GB"', () => expect(_freeStr(10.0), '10 GB'));
    test('500.0 GB → "500 GB"', () => expect(_freeStr(500.0), '500 GB'));
    test('999.0 GB → "999 GB"', () => expect(_freeStr(999.0), '999 GB'));
    test('1.4 GB → "1 GB" (toStringAsFixed(0) truncates)', () =>
        expect(_freeStr(1.4), '1 GB'));
    test('1.9 GB → "2 GB" (toStringAsFixed(0) rounds)', () =>
        expect(_freeStr(1.9), '2 GB'));
  });

  group('library — _freeStr: TB range (>= 1000 GB)', () {
    test('1000 GB → "1.00 TB"', () => expect(_freeStr(1000.0), '1.00 TB'));
    test('2000 GB → "2.00 TB"', () => expect(_freeStr(2000.0), '2.00 TB'));
    test('2500 GB → "2.50 TB"', () => expect(_freeStr(2500.0), '2.50 TB'));
    test('1500 GB → "1.50 TB"', () => expect(_freeStr(1500.0), '1.50 TB'));
  });

  group('library — _freeStr: MB range (< 1 GB)', () {
    test('0.0 GB → "0 MB"', () => expect(_freeStr(0.0), '0 MB'));
    test('0.1 GB → "100 MB"', () => expect(_freeStr(0.1), '100 MB'));
    test('0.5 GB → "500 MB"', () => expect(_freeStr(0.5), '500 MB'));
    test('0.999 GB → "999 MB"', () => expect(_freeStr(0.999), '999 MB'));
  });

  // ── _diskColor() threshold tests ──────────────────────────────────────────

  group('library — disk color: green (safe)', () {
    test('pct = 0 → green', () => expect(_diskColorName(0), 'green'));
    test('pct = 50 → green', () => expect(_diskColorName(50), 'green'));
    test('pct = 70 → green (threshold is > 70, not >=)', () =>
        expect(_diskColorName(70), 'green'));
  });

  group('library — disk color: yellow (moderate)', () {
    test('pct = 70.001 → yellow', () => expect(_diskColorName(70.001), 'yellow'));
    test('pct = 75 → yellow', () => expect(_diskColorName(75), 'yellow'));
    test('pct = 80 → yellow (threshold is > 80, not >=)', () =>
        expect(_diskColorName(80), 'yellow'));
  });

  group('library — disk color: orange (warning)', () {
    test('pct = 80.001 → orange', () => expect(_diskColorName(80.001), 'orange'));
    test('pct = 83 → orange', () => expect(_diskColorName(83), 'orange'));
    test('pct = 85 → orange (threshold is > 85, not >=)', () =>
        expect(_diskColorName(85), 'orange'));
  });

  group('library — disk color: red (critical)', () {
    test('pct = 85.001 → red', () => expect(_diskColorName(85.001), 'red'));
    test('pct = 90 → red', () => expect(_diskColorName(90), 'red'));
    test('pct = 100 → red', () => expect(_diskColorName(100), 'red'));
  });

  group('library — disk bar visibility', () {
    test('total_gb = 0 → disk bar hidden', () {
      final Map<String, dynamic> disk = <String, dynamic>{'total_gb': 0};
      final num total = (disk['total_gb'] as num?) ?? 0;
      expect(total > 0, isFalse);
    });

    test('total_gb > 0 → disk bar shown', () {
      final Map<String, dynamic> disk = <String, dynamic>{'total_gb': 8000};
      final num total = (disk['total_gb'] as num?) ?? 0;
      expect(total > 0, isTrue);
    });

    test('used_pct is read from disk response', () {
      final Map<String, dynamic> disk = <String, dynamic>{
        'total_gb': 8000, 'free_gb': 1600, 'used_pct': 80.0,
      };
      final double pct = (disk['used_pct'] as num?)?.toDouble() ?? 0;
      expect(pct, 80.0);
    });

    test('missing used_pct defaults to 0', () {
      final Map<String, dynamic> disk = <String, dynamic>{'total_gb': 8000};
      final double pct = (disk['used_pct'] as num?)?.toDouble() ?? 0;
      expect(pct, 0.0);
    });
  });

  group('library — free_gb display (via _freeStr)', () {
    test('1600 GB free → "1.60 TB" (>= 1000 → TB)', () => expect(_freeStr(1600.0), '1.60 TB'));
    test('0 free → "0 MB"', () => expect(_freeStr(0.0), '0 MB'));
  });
}
