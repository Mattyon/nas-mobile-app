import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Exact copy of internal logic from _DownloadsScreenState ──────────────

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

  String _eta(Object? s) {
    final int sec = (s is num) ? s.toInt() : 0;
    if (sec <= 0 || sec >= 8640000) return '∞';
    final int h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  const Map<String, String> _stateLabel = <String, String>{
    'downloading':  'Downloading',
    'forcedDL':     'Downloading',
    'stalledDL':    'Stalled — no peers',
    'metaDL':       'Fetching metadata',
    'checkingDL':   'Checking',
    'allocating':   'Allocating',
    'queuedDL':     'Queued',
    'pausedDL':     'Paused',
    'stoppedDL':    'Stopped',
    'uploading':    'Seeding',
    'forcedUP':     'Seeding',
    'stalledUP':    'Seeding (stalled)',
    'checkingUP':   'Checking',
    'pausedUP':     'Paused',
    'stoppedUP':    'Stopped',
    'error':        'Error',
    'missingFiles': 'Missing files',
    'moving':       'Moving',
    'unknown':      'Unknown',
  };

  // ── _group() ──────────────────────────────────────────────────────────────

  group('downloads — group 0 (active downloading)', () {
    const List<String> group0 = <String>[
      'downloading', 'forcedDL', 'metaDL', 'stalledDL', 'checkingDL', 'allocating',
    ];
    for (final String state in group0) {
      test('"$state" → group 0', () => expect(_group(state), 0));
    }
  });

  group('downloads — group 1 (queued)', () {
    test('"queuedDL" → group 1', () => expect(_group('queuedDL'), 1));
  });

  group('downloads — group 2 (finished / seeding / paused)', () {
    const List<String> group2 = <String>[
      'uploading', 'forcedUP', 'stalledUP', 'checkingUP',
      'pausedDL', 'stoppedDL', 'pausedUP', 'stoppedUP',
      'moving', 'unknown',
    ];
    for (final String state in group2) {
      test('"$state" → group 2', () => expect(_group(state), 2));
    }
    test('unrecognised state → group 2 (default)', () {
      expect(_group('neverHeardOf'), 2);
    });
  });

  group('downloads — group 3 (failed)', () {
    test('"error" → group 3', () => expect(_group('error'), 3));
    test('"missingFiles" → group 3', () => expect(_group('missingFiles'), 3));
  });

  group('downloads — active tab gets groups 0 and 1 only', () {
    test('active tab includes group 0 states', () {
      for (final String s in _activeStates) {
        expect(_group(s) <= 1, isTrue, reason: '"$s" must be in active tab');
      }
    });
    test('active tab includes queuedDL', () {
      expect(_group('queuedDL') <= 1, isTrue);
    });
    test('active tab excludes group 2 states', () {
      for (final String s in <String>['uploading', 'stoppedUP', 'pausedUP']) {
        expect(_group(s) <= 1, isFalse, reason: '"$s" must not be in active tab');
      }
    });
    test('active tab excludes failed states', () {
      for (final String s in _failedStates) {
        expect(_group(s) <= 1, isFalse, reason: '"$s" must not be in active tab');
      }
    });
  });

  group('downloads — finished tab gets groups 2 and 3', () {
    test('finished tab includes uploading/seeding', () {
      expect(_group('uploading') > 1, isTrue);
    });
    test('finished tab includes failed states', () {
      for (final String s in _failedStates) {
        expect(_group(s) > 1, isTrue, reason: '"$s" must appear in finished tab');
      }
    });
    test('failed sorts after finished: group 3 > group 2', () {
      expect(_group('error'), greaterThan(_group('uploading')));
      expect(_group('missingFiles'), greaterThan(_group('stoppedUP')));
    });
  });

  // ── _eta() ────────────────────────────────────────────────────────────────

  group('downloads — ETA: infinity cases', () {
    test('0 → ∞', () => expect(_eta(0), '∞'));
    test('negative → ∞', () => expect(_eta(-1), '∞'));
    test('null → ∞', () => expect(_eta(null), '∞'));
    test('non-numeric string → ∞', () => expect(_eta('abc'), '∞'));
    test('8640000 exactly → ∞', () => expect(_eta(8640000), '∞'));
    test('8640001 → ∞', () => expect(_eta(8640001), '∞'));
  });

  group('downloads — ETA: seconds display', () {
    test('1s → "1s"', () => expect(_eta(1), '1s'));
    test('30s → "30s"', () => expect(_eta(30), '30s'));
    test('59s → "59s"', () => expect(_eta(59), '59s'));
  });

  group('downloads — ETA: minutes display', () {
    test('60s → "1m"', () => expect(_eta(60), '1m'));
    test('90s → "1m"', () => expect(_eta(90), '1m'));
    test('3599s → "59m"', () => expect(_eta(3599), '59m'));
  });

  group('downloads — ETA: hours+minutes display', () {
    test('3600s → "1h 0m"', () => expect(_eta(3600), '1h 0m'));
    test('3661s → "1h 1m"', () => expect(_eta(3661), '1h 1m'));
    test('7322s → "2h 2m"', () => expect(_eta(7322), '2h 2m'));
    test('86399s → "23h 59m"', () => expect(_eta(86399), '23h 59m'));
  });

  group('downloads — ETA: double value coerced to int', () {
    test('90.9 → "1m" (coerced to 90)', () => expect(_eta(90.9), '1m'));
    test('3600.0 → "1h 0m"', () => expect(_eta(3600.0), '1h 0m'));
  });

  // ── _stateLabel coverage ──────────────────────────────────────────────────

  group('downloads — state label coverage', () {
    test('all active states have labels', () {
      for (final String s in _activeStates) {
        expect(_stateLabel[s], isNotNull, reason: '"$s" missing label');
      }
    });
    test('both failed states have labels', () {
      for (final String s in _failedStates) {
        expect(_stateLabel[s], isNotNull, reason: '"$s" missing label');
      }
    });
    test('queuedDL has label', () => expect(_stateLabel['queuedDL'], isNotNull));
    test('all labels are non-empty', () {
      for (final MapEntry<String, String> entry in _stateLabel.entries) {
        expect(entry.value, isNotEmpty, reason: '"${entry.key}" has empty label');
      }
    });
  });
}
