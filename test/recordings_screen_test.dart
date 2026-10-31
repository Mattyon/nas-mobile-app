import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/recordings_screen.dart';

// Camera recordings for the superadmin (owner, 2026-10-28): storage per camera and in total,
// and playback from a picked day and time, with the camera's sound (2026-10-31).

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

// The video from 11:10: a minute, then (after a gap) from 11:20 on.
Future<Map<String, dynamic>> _plan(String cam, String at) async => <String, dynamic>{
      'start': at,
      'pieces': <Map<String, dynamic>>[
        <String, dynamic>{'start': at, 'seconds': 60},
        <String, dynamic>{'start': '2026-10-28T11:20:00', 'seconds': 600},
      ],
    };

class _FakeVideo extends ChangeNotifier implements RecordingVideo {
  @override
  Duration position = Duration.zero;
  @override
  bool ended = false;
  @override
  String? error;
  bool paused = false;
  bool disposed = false;

  @override
  Future<void> open() async {}
  @override
  Widget view() => const SizedBox(key: ValueKey<String>('fake-video'));
  @override
  void pause() => paused = true;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  void play(Duration to) {
    position = to;
    notifyListeners();
  }

  void end() {
    ended = true;
    notifyListeners();
  }
}

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

  test('the clock jumps over the gaps the video leaves out', () {
    final List<Piece> pieces = <Piece>[(DateTime(2026, 10, 28, 11, 10), 60), (DateTime(2026, 10, 28, 11, 20), 600)];
    expect(momentIn(pieces, const Duration(seconds: 30)), DateTime(2026, 10, 28, 11, 10, 30));
    expect(momentIn(pieces, const Duration(seconds: 90)), DateTime(2026, 10, 28, 11, 20, 30));
    // past the last stretch's expected end: still counts on from it
    expect(momentIn(pieces, const Duration(seconds: 700)), DateTime(2026, 10, 28, 11, 30, 40));
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
    final List<String> planned = <String>[];
    final List<(String, bool)> opened = <(String, bool)>[];
    final List<_FakeVideo> videos = <_FakeVideo>[];
    await t.pumpWidget(MaterialApp(
      home: RecordingPlayerScreen(
        id: 'c1',
        name: 'Tweety',
        loadDay: _day,
        loadPlan: (String cam, String at) {
          planned.add(at);
          return _plan(cam, at);
        },
        openVideo: (String cam, String at, bool hd) {
          opened.add((at, hd));
          return (videos..add(_FakeVideo())).last;
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
    expect(planned, <String>['2026-10-28T11:10:00']);
    expect(opened, <(String, bool)>[('2026-10-28T11:10:00', true)]);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('fake-video')), findsOneWidget);
    // a minute and a half in: past the gap, so 11:20:30, not 11:11:30
    videos.single.play(const Duration(seconds: 90));
    await t.pump();
    expect(find.text('28.10.2026 11:20:30'), findsOneWidget);
    // pause: the picture stays, and play goes on from there
    await t.tap(find.byKey(const ValueKey<String>('recording-play')));
    await t.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(videos.single.paused && !videos.single.disposed, isTrue);
    expect(find.byKey(const ValueKey<String>('fake-video')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('recording-play')));
    await t.pump();
    expect(planned.last, '2026-10-28T11:20:30');
    expect(videos.first.disposed, isTrue);   // the new one is open: the still goes
    // the end of the recordings
    videos.last.end();
    await t.pump();
    expect(find.text('End of the recordings'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('a video that fails says so', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final _FakeVideo v = _FakeVideo();
    await t.pumpWidget(MaterialApp(
      home: RecordingPlayerScreen(id: 'c1', name: 'Tweety', loadDay: _day, loadPlan: _plan,
          openVideo: (String c, String at, bool hd) => v),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('recording-play')));
    await t.pump();
    v
      ..error = 'Source error'
      ..notifyListeners();
    await t.pump();
    expect(find.text('Source error'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(v.disposed, isTrue);
  });

  testWidgets('full screen: landscape, bars hidden, back leaves it', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final List<MethodCall> calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(MaterialApp(
      home: RecordingPlayerScreen(id: 'c1', name: 'Tweety', loadDay: _day, loadPlan: _plan,
          openVideo: (String c, String at, bool hd) => _FakeVideo()),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('recording-full')));
    await t.pump();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey<String>('recording-exit-full')), findsOneWidget);
    expect(calls.map((MethodCall c) => c.method), containsAll(<String>[
      'SystemChrome.setPreferredOrientations', 'SystemChrome.setEnabledSystemUIMode']));
    expect(calls.firstWhere((MethodCall c) => c.method == 'SystemChrome.setPreferredOrientations').arguments,
        <String>['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);
    // a tap hides the controls, another shows them
    await t.tap(find.byKey(const ValueKey<String>('recording-full-area')));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('recording-exit-full')), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('recording-full-area')));
    await t.pump();
    // the phone's back button leaves full screen, not the player
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Tweety'), findsOneWidget);
  });

  test('every string in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      for (final String k in <String>['cameraRecordings', 'recordingsTotal', 'recordingsFree', 'recordingsFull',
          'recordingsArchive', 'recordingsSince', 'recordingsPlay', 'recordingsPause', 'recordingsPickTime',
          'recordingsEnd', 'recordingsWebOnly', 'fullScreen']) {
        expect(tr(k), isNot(equals(k)), reason: '$l $k');
      }
    }
  });
}
