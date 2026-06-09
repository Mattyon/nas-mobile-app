import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Exact logic from _DownloadsScreenState._subtitleStats() ──────────────

  const Set<String> _seedingStates = <String>{
    'uploading', 'forcedUP', 'stalledUP'
  };

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

  String _eta(Object? s) {
    final int sec = (s is num) ? s.toInt() : 0;
    if (sec <= 0 || sec >= 8640000) return '∞';
    final int h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  String _subtitleStats(Map<String, dynamic> t) {
    final double pct = (t['progress'] as num?)?.toDouble() ?? 0;
    final String state = t['state']?.toString() ?? '';
    final String label = _stateLabel[state] ?? state;
    if (_seedingStates.contains(state)) {
      final num up = (t['upspeed_mbs'] as num?) ?? 0;
      final num ratio = (t['ratio'] as num?) ?? 0;
      return '${pct.toStringAsFixed(1)}%  •  ↑ $up MB/s  •  Ratio ${ratio.toStringAsFixed(2)}  •  $label';
    }
    return '${pct.toStringAsFixed(1)}%  •  ${t['dlspeed_mbs'] ?? 0} MB/s  •  '
        'ETA ${_eta(t['eta_sec'])}  •  $label';
  }

  // ── _seedingStates membership ─────────────────────────────────────────────

  group('seeding stats — _seedingStates set', () {
    test('uploading is a seeding state', () =>
        expect(_seedingStates.contains('uploading'), isTrue));
    test('forcedUP is a seeding state', () =>
        expect(_seedingStates.contains('forcedUP'), isTrue));
    test('stalledUP is a seeding state', () =>
        expect(_seedingStates.contains('stalledUP'), isTrue));
    test('downloading is NOT a seeding state', () =>
        expect(_seedingStates.contains('downloading'), isFalse));
    test('stoppedUP is NOT a seeding state (stopped, not actively seeding)', () =>
        expect(_seedingStates.contains('stoppedUP'), isFalse));
    test('pausedUP is NOT a seeding state', () =>
        expect(_seedingStates.contains('pausedUP'), isFalse));
    test('error is NOT a seeding state', () =>
        expect(_seedingStates.contains('error'), isFalse));
  });

  // ── Seeding state subtitle format ─────────────────────────────────────────

  group('seeding stats — uploading state shows upload speed + ratio', () {
    final Map<String, dynamic> t = <String, dynamic>{
      'state': 'uploading',
      'progress': 100.0,
      'upspeed_mbs': 0.45,
      'ratio': 1.23,
      'dlspeed_mbs': 0,
      'eta_sec': 0,
    };

    test('contains upload arrow', () => expect(_subtitleStats(t), contains('↑')));
    test('contains upload speed', () => expect(_subtitleStats(t), contains('0.45 MB/s')));
    test('contains ratio', () => expect(_subtitleStats(t), contains('Ratio 1.23')));
    test('contains state label "Seeding"', () => expect(_subtitleStats(t), contains('Seeding')));
    test('does NOT contain "ETA"', () => expect(_subtitleStats(t), isNot(contains('ETA'))));
    test('exact format', () =>
        expect(_subtitleStats(t), '100.0%  •  ↑ 0.45 MB/s  •  Ratio 1.23  •  Seeding'));
  });

  group('seeding stats — forcedUP state shows upload speed + ratio', () {
    final Map<String, dynamic> t = <String, dynamic>{
      'state': 'forcedUP',
      'progress': 100.0,
      'upspeed_mbs': 1.5,
      'ratio': 0.5,
    };

    test('shows upload speed', () => expect(_subtitleStats(t), contains('↑ 1.5 MB/s')));
    test('shows ratio', () => expect(_subtitleStats(t), contains('Ratio 0.50')));
    test('shows Seeding label', () => expect(_subtitleStats(t), contains('Seeding')));
  });

  group('seeding stats — stalledUP state shows upload speed + ratio', () {
    final Map<String, dynamic> t = <String, dynamic>{
      'state': 'stalledUP',
      'progress': 100.0,
      'upspeed_mbs': 0.0,
      'ratio': 2.1,
    };

    test('shows stalled label', () =>
        expect(_subtitleStats(t), contains('Seeding (stalled)')));
    test('shows ratio even when stalled', () =>
        expect(_subtitleStats(t), contains('Ratio 2.10')));
  });

  // ── Seeding state: missing / null fields fall back to 0 ───────────────────

  group('seeding stats — null field fallbacks', () {
    test('null upspeed_mbs falls back to 0', () {
      final Map<String, dynamic> t = <String, dynamic>{
        'state': 'uploading',
        'progress': 100.0,
        'upspeed_mbs': null,
        'ratio': 1.0,
      };
      expect(_subtitleStats(t), contains('↑ 0 MB/s'));
    });

    test('missing upspeed_mbs falls back to 0', () {
      final Map<String, dynamic> t = <String, dynamic>{
        'state': 'uploading',
        'progress': 100.0,
        'ratio': 1.0,
      };
      expect(_subtitleStats(t), contains('↑ 0 MB/s'));
    });

    test('null ratio falls back to 0.00', () {
      final Map<String, dynamic> t = <String, dynamic>{
        'state': 'uploading',
        'progress': 100.0,
        'upspeed_mbs': 0.5,
        'ratio': null,
      };
      expect(_subtitleStats(t), contains('Ratio 0.00'));
    });

    test('missing ratio falls back to 0.00', () {
      final Map<String, dynamic> t = <String, dynamic>{
        'state': 'uploading',
        'progress': 100.0,
        'upspeed_mbs': 0.5,
      };
      expect(_subtitleStats(t), contains('Ratio 0.00'));
    });
  });

  // ── Non-seeding states keep DL speed + ETA format ─────────────────────────

  group('seeding stats — downloading state keeps DL speed + ETA', () {
    final Map<String, dynamic> t = <String, dynamic>{
      'state': 'downloading',
      'progress': 45.0,
      'dlspeed_mbs': 3.2,
      'eta_sec': 3661,
      'upspeed_mbs': 0,
      'ratio': 0,
    };

    test('contains DL speed', () => expect(_subtitleStats(t), contains('3.2 MB/s')));
    test('contains ETA', () => expect(_subtitleStats(t), contains('ETA 1h 1m')));
    test('does NOT contain upload arrow', () =>
        expect(_subtitleStats(t), isNot(contains('↑'))));
    test('does NOT contain Ratio', () =>
        expect(_subtitleStats(t), isNot(contains('Ratio'))));
    test('exact format', () =>
        expect(_subtitleStats(t), '45.0%  •  3.2 MB/s  •  ETA 1h 1m  •  Downloading'));
  });

  group('seeding stats — stoppedUP shows DL format (not seeding)', () {
    final Map<String, dynamic> t = <String, dynamic>{
      'state': 'stoppedUP',
      'progress': 100.0,
      'dlspeed_mbs': 0,
      'eta_sec': 0,
    };

    test('contains ETA ∞ (stopped, no ETA)', () =>
        expect(_subtitleStats(t), contains('ETA ∞')));
    test('does NOT contain upload arrow', () =>
        expect(_subtitleStats(t), isNot(contains('↑'))));
  });

  group('seeding stats — error state shows DL format', () {
    final Map<String, dynamic> t = <String, dynamic>{
      'state': 'error',
      'progress': 50.0,
      'dlspeed_mbs': 0,
      'eta_sec': 0,
    };

    test('shows Error label', () => expect(_subtitleStats(t), contains('Error')));
    test('does NOT show Ratio', () =>
        expect(_subtitleStats(t), isNot(contains('Ratio'))));
  });

  // ── Ratio formatting: always 2 decimal places ─────────────────────────────

  group('seeding stats — ratio always renders with 2 decimal places', () {
    String ratio(double r) => _subtitleStats(<String, dynamic>{
          'state': 'uploading', 'progress': 100.0, 'upspeed_mbs': 0, 'ratio': r,
        });

    test('0.0 → "0.00"', () => expect(ratio(0.0), contains('Ratio 0.00')));
    test('1.0 → "1.00"', () => expect(ratio(1.0), contains('Ratio 1.00')));
    test('2.5 → "2.50"', () => expect(ratio(2.5), contains('Ratio 2.50')));
    test('10.99 → "10.99"', () => expect(ratio(10.99), contains('Ratio 10.99')));
  });
}
