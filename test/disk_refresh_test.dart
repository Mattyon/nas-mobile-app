import 'package:flutter_test/flutter_test.dart';

/// Mirrors _LibraryScreenState._pollDiskSpace(): after a delete, Radarr/Sonarr
/// remove files asynchronously, so /diskspace keeps reporting the OLD free space
/// for a moment. The screen re-reads it until the number moves (bounded), instead
/// of leaving a stale disk bar until the user pulls to refresh.
void main() {
  const int maxPolls = 8;

  /// Returns the readings actually consumed before the poller stopped.
  List<double> runPoll(double freeBefore, List<double> readings) {
    final List<double> consumed = <double>[];
    for (int i = 0; i < maxPolls && i < readings.length; i++) {
      final double now = readings[i];
      consumed.add(now);
      if (now > freeBefore) break; // space was freed — done
    }
    return consumed;
  }

  group('disk space polling after a delete', () {
    test('stops as soon as free space increases', () {
      final List<double> consumed = runPoll(20, <double>[20, 20, 70, 70, 70]);
      expect(consumed, <double>[20, 20, 70]);
    });

    test('stops on the first reading when the delete is already reflected', () {
      expect(runPoll(20, <double>[70]).length, 1);
    });

    test('gives up after maxPolls when the value never moves', () {
      final List<double> consumed =
          runPoll(20, List<double>.filled(20, 20));
      expect(consumed.length, maxPolls);
    });

    test('a shrinking value does not count as freed space', () {
      // Something else is writing (a download); that must not end the poll early.
      final List<double> consumed = runPoll(20, <double>[19, 18, 17]);
      expect(consumed.length, 3);
    });

    test('equal value does not end the poll', () {
      expect(runPoll(20, <double>[20, 20]).length, 2);
    });
  });
}
