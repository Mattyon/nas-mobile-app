import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/recordings_screen.dart';

// Camera recordings for the superadmin (owner, 2026-10-28): storage per camera and in total,
// and playback from a picked day and time.

final Map<String, dynamic> _storage = <String, dynamic>{
  'cameras': <Map<String, dynamic>>[
    <String, dynamic>{'id': 'c1', 'name': 'Tweety', 'full_bytes': 50 * 1024 * 1024 * 1024,
      'archive_bytes': 3 * 1024 * 1024 * 1024, 'total_bytes': 53 * 1024 * 1024 * 1024,
      'oldest': '2026-10-27T12:48:07', 'newest': '2026-10-28T11:30:00'},
  ],
  'total_bytes': 53 * 1024 * 1024 * 1024,
  'free_bytes': 8 * 1024 * 1024 * 1024 * 1024,
};

Future<Map<String, dynamic>> _day(String cam, String? day) async => <String, dynamic>{
      'day': day ?? '2026-10-28',
      'days': <String>['2026-10-27', '2026-10-28'],
      'segments': <Map<String, dynamic>>[
        <String, dynamic>{'start': '2026-10-28T00:00:00', 'end': '2026-10-28T11:30:00', 'quality': 'full'},
      ],
    };

void main() {
  setUp(() => lang.value = 'en');

  test('sizes read like the rest of the app', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(354 * 1024 * 1024), '354 MB');
    expect(formatBytes(53 * 1024 * 1024 * 1024), '53.0 GB');
    expect(formatBytes(1.2 * 1024 * 1024 * 1024 * 1024), '1.2 TB');
  });

  test('moments go to the gateway on the NAS clock', () {
    expect(wallClock(DateTime(2026, 10, 28, 9, 5, 3)), '2026-10-28T09:05:03');
  });

  test('a tap on the timeline is that moment of the day', () {
    final DateTime d = DateTime(2026, 10, 28);
    expect(DayTimeline.at(d, 0.5), DateTime(2026, 10, 28, 12));
    expect(DayTimeline.at(d, 0), DateTime(2026, 10, 28));
    expect(DayTimeline.at(d, 2).day, 28);   // never past the day
  });

  testWidgets('storage: the total, what is free, each camera', (WidgetTester t) async {
    await t.pumpWidget(MaterialApp(home: RecordingsScreen(load: () async => _storage)));
    await t.pumpAndSettle();
    expect(find.text('All cameras: 53.0 GB'), findsOneWidget);
    expect(find.text('Free on the NAS: 8.0 TB'), findsOneWidget);
    expect(find.textContaining('Full quality 50.0 GB · Archive 720p 3.0 GB · since 27.10.2026'), findsOneWidget);
  });

  testWidgets('player: opens on the newest day, jumps, plays from the chosen moment', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final List<(String, bool)> asked = <(String, bool)>[];
    final StreamController<Uint8List> frames = StreamController<Uint8List>();
    await t.pumpWidget(MaterialApp(
      home: RecordingPlayerScreen(
        id: 'c1',
        name: 'Tweety',
        loadDay: _day,
        play: (String cam, String at, bool hd, CancelToken cancel) async {
          asked.add((at, hd));
          return (frames.stream, DateTime.parse(at));
        },
      ),
    ));
    await t.pumpAndSettle();
    // the newest day, five minutes before its last recording
    expect(find.text('28.10.2026 11:25:00'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('recording-jump-15m')));
    await t.pump();
    expect(find.text('28.10.2026 11:10:00'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('recording-hd')));
    await t.tap(find.byKey(const ValueKey<String>('recording-play')));
    await t.pump();
    expect(asked, <(String, bool)>[('2026-10-28T11:10:00', true)]);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('recording-play')));   // pause
    await t.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    unawaited(frames.close());   // paused: the screen already let go of it
  });

  test('every string in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      for (final String k in <String>['cameraRecordings', 'recordingsTotal', 'recordingsFree', 'recordingsFull',
          'recordingsArchive', 'recordingsSince', 'recordingsPlay', 'recordingsPause', 'recordingsPickTime',
          'recordingsEnd', 'recordingsWebOnly']) {
        expect(tr(k), isNot(equals(k)), reason: '$l $k');
      }
    }
  });
}
