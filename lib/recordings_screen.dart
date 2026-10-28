import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'i18n.dart';

// Camera recordings (owner, 2026-10-28: "superadmin should see how much storage is spent on
// cameras (per camera + total), and be able to watch the history of recordings (and choose
// quality), with the possibility of picking the date and time"). Superadmin only, like the
// cameras. The first page lists what each camera's recordings take; a camera opens the
// player: pick a day (only days with recordings) and a time, or tap the day's timeline, and
// it plays from there on -- MJPEG from the gateway, like the live view, so no sound -- in SD
// or HD, also full screen (landscape, the phone's bars hidden; tap for the controls; back
// leaves it -- owner, 2026-10-28). Times are the NAS's clock. The web build shows the storage only: Dio on the web
// cannot read an endless response (the live view keeps snapshots there for the same reason).

typedef StorageLoader = Future<Map<String, dynamic>> Function();
typedef DayLoader = Future<Map<String, dynamic>> Function(String camId, String? day);
typedef Player = Future<(Stream<Uint8List>, DateTime)> Function(
    String camId, String at, bool hd, CancelToken cancel);

/// Human-readable size: 354 MB, 35.6 GB, 1.2 TB.
String formatBytes(num bytes) {
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double b = bytes.toDouble();
  int i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(i >= 3 ? 1 : 0)} ${units[i]}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The gateway's form of a moment on the NAS clock: 2026-10-28T10:05:00.
String wallClock(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

String isoDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String clockText(DateTime d) =>
    '${d.day}.${d.month}.${d.year} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// A recorded stretch of one day.
class Stretch {
  const Stretch(this.start, this.end, {this.archive = false});
  final DateTime start;
  final DateTime end;
  final bool archive;
}

List<Stretch> parseStretches(Object? segments) => <Stretch>[
      for (final Object? s in (segments as List<dynamic>?) ?? <dynamic>[])
        if (s is Map<String, dynamic>)
          Stretch(DateTime.parse(s['start'] as String), DateTime.parse(s['end'] as String),
              archive: s['quality'] == 'archive'),
    ];

// ── storage ──────────────────────────────────────────────────────────────────

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, this.load});

  /// Injectable for tests; defaults to the gateway.
  final StorageLoader? load;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with LangAware {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _error = null);
    try {
      final Map<String, dynamic> d = await (widget.load ?? Api.I.recordingsStorage)();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? d = _data;
    final List<Map<String, dynamic>> cams =
        ((d?['cameras'] as List<dynamic>?) ?? <dynamic>[]).whereType<Map<String, dynamic>>().toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('cameraRecordings')),
        actions: <Widget>[IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch)],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: <Widget>[
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: ListTile(
                        key: const ValueKey<String>('recordings-total'),
                        leading: const Icon(Icons.storage_outlined),
                        title: Text('${tr('recordingsTotal')}: ${formatBytes((d['total_bytes'] as num?) ?? 0)}'),
                        subtitle: d['free_bytes'] == null
                            ? null
                            : Text('${tr('recordingsFree')}: ${formatBytes(d['free_bytes'] as num)}'),
                      ),
                    ),
                    if (cams.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(tr('noCameras'), style: const TextStyle(color: Colors.grey))),
                      ),
                    for (final Map<String, dynamic> c in cams)
                      ListTile(
                        key: ValueKey<String>('recordings-${c['id']}'),
                        leading: const Icon(Icons.videocam_outlined),
                        title: Text('${c['name']}'),
                        subtitle: Text(<String>[
                          '${tr('recordingsFull')} ${formatBytes((c['full_bytes'] as num?) ?? 0)}',
                          '${tr('recordingsArchive')} ${formatBytes((c['archive_bytes'] as num?) ?? 0)}',
                          if (c['oldest'] != null)
                            '${tr('recordingsSince')} ${clockText(DateTime.parse(c['oldest'] as String)).split(' ').first}',
                        ].join(' · ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          Text(formatBytes((c['total_bytes'] as num?) ?? 0),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (!kIsWeb) const Icon(Icons.chevron_right),
                        ]),
                        onTap: kIsWeb || c['oldest'] == null
                            ? null
                            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => RecordingPlayerScreen(id: '${c['id']}', name: '${c['name']}'))),
                      ),
                    if (kIsWeb)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(tr('recordingsWebOnly'), style: TextStyle(color: Colors.grey[500])),
                      ),
                  ],
                ),
    );
  }
}

// ── player ───────────────────────────────────────────────────────────────────

class RecordingPlayerScreen extends StatefulWidget {
  const RecordingPlayerScreen({super.key, required this.id, required this.name, this.loadDay, this.play});
  final String id;
  final String name;

  /// Injectable for tests; default to the gateway.
  final DayLoader? loadDay;
  final Player? play;

  @override
  State<RecordingPlayerScreen> createState() => _RecordingPlayerScreenState();
}

class _RecordingPlayerScreenState extends State<RecordingPlayerScreen> with LangAware {
  List<String> _days = <String>[];
  DateTime? _day;
  List<Stretch> _stretches = <Stretch>[];
  DateTime? _at;                 // where playback starts, or where it was paused
  bool _hd = false;
  bool _playing = false;
  bool _ended = false;
  String? _error;
  Uint8List? _frame;
  DateTime? _playStart;
  final Stopwatch _clock = Stopwatch();
  CancelToken? _cancel;
  StreamSubscription<Uint8List>? _sub;
  Timer? _tick;
  bool _full = false;
  bool _controls = true;   // full screen: the overlay, shown and hidden by a tap

  DayLoader get _loadDay => widget.loadDay ?? Api.I.cameraRecordings;
  Player get _player => widget.play ?? Api.I.cameraPlayback;

  /// What the picture shows now: the start plus the time played (frames come at real time).
  DateTime? get _position =>
      _playing && _playStart != null ? _playStart!.add(_clock.elapsed) : _at;

  @override
  void initState() {
    super.initState();
    _fetchDay(null);
  }

  @override
  void dispose() {
    _stop();
    _tick?.cancel();
    if (_full) _systemUi(full: false);
    super.dispose();
  }

  static void _systemUi({required bool full}) {
    SystemChrome.setPreferredOrientations(full
        ? <DeviceOrientation>[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : <DeviceOrientation>[]);   // empty: whatever the phone allows again
    SystemChrome.setEnabledSystemUIMode(full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  void _setFull(bool full) {
    _systemUi(full: full);
    setState(() {
      _full = full;
      _controls = true;
    });
  }

  Future<void> _fetchDay(String? day) async {
    try {
      final Map<String, dynamic> d = await _loadDay(widget.id, day);
      if (!mounted) return;
      final List<Stretch> s = parseStretches(d['segments']);
      setState(() {
        _days = ((d['days'] as List<dynamic>?) ?? <dynamic>[]).map((Object? x) => '$x').toList();
        _day = DateTime.parse(d['day'] as String);
        _stretches = s;
        // A new day starts where its first recording does; the newest day at its last hour.
        if (_at == null || isoDay(_at!) != isoDay(_day!)) {
          _at = s.isEmpty
              ? _day
              : (day == null ? s.last.end.subtract(const Duration(minutes: 5)) : s.first.start);
          if (_at!.isBefore(s.isEmpty ? _day! : s.first.start)) _at = s.first.start;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _cancel?.cancel();
    _cancel = null;
    _clock.stop();
    _tick?.cancel();
  }

  Future<void> _play() async {
    final DateTime? at = _at;
    if (at == null) return;
    _stop();
    final CancelToken cancel = _cancel = CancelToken();
    setState(() { _playing = true; _ended = false; _error = null; });
    try {
      final (Stream<Uint8List> frames, DateTime start) = await _player(widget.id, wallClock(at), _hd, cancel);
      if (!mounted || cancel.isCancelled) return;
      _playStart = start;
      _clock
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
      _sub = frames.listen(
        (Uint8List f) { if (mounted) setState(() => _frame = f); },
        onError: (Object e) { if (mounted && !cancel.isCancelled) _pause(error: e.toString()); },
        onDone: () { if (mounted && !cancel.isCancelled) _pause(ended: true); },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted && !cancel.isCancelled) _pause(error: e.toString());
    }
  }

  void _pause({String? error, bool ended = false}) {
    final DateTime? pos = _position;
    _stop();
    setState(() {
      _at = pos;
      _playing = false;
      _ended = ended;
      _error = error;
    });
  }

  void _seek(DateTime to) {
    final bool resume = _playing;
    if (_playing) _pause();
    setState(() => _at = to);
    if (isoDay(to) != isoDay(_day ?? to)) _fetchDay(isoDay(to));
    if (resume) _play();
  }

  Future<void> _pickDay() async {
    if (_days.isEmpty || _day == null) return;
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _day!,
      firstDate: DateTime.parse(_days.first),
      lastDate: DateTime.parse(_days.last),
      selectableDayPredicate: (DateTime d) => _days.contains(isoDay(d)),
    );
    if (d == null) return;
    if (_playing) _pause();
    _at = null;
    await _fetchDay(isoDay(d));
  }

  Future<void> _pickTime() async {
    final DateTime base = _position ?? _day ?? DateTime.now();
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      builder: (BuildContext c, Widget? child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    final DateTime day = _day ?? base;
    _seek(DateTime(day.year, day.month, day.day, t.hour, t.minute));
    if (!_playing) _play();
  }

  Widget _picture({BoxFit fit = BoxFit.contain}) => _frame != null
      ? InteractiveViewer(child: Image.memory(_frame!, gaplessPlayback: true, fit: fit))
      : Icon(_playing ? Icons.hourglass_empty : Icons.play_circle_outline, size: 56, color: Colors.white38);

  Widget _fullScreen(DateTime? pos) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _setFull(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            key: const ValueKey<String>('recording-full-area'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _controls = !_controls),
            child: Stack(children: <Widget>[
              Positioned.fill(child: Center(child: _picture())),
              if (_controls) ...<Widget>[
                Positioned(
                  top: 16, left: 16,
                  child: Text(pos == null ? '' : '${widget.name}  ${clockText(pos)}',
                      style: const TextStyle(color: Colors.white, fontSize: 16,
                          shadows: <Shadow>[Shadow(blurRadius: 4)])),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: IconButton(
                    key: const ValueKey<String>('recording-exit-full'),
                    color: Colors.white,
                    icon: const Icon(Icons.fullscreen_exit),
                    onPressed: () => _setFull(false),
                  ),
                ),
                Positioned(
                  bottom: 16, left: 0, right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                    _jump('-1m', const Duration(minutes: -1), color: Colors.white),
                    const SizedBox(width: 24),
                    IconButton.filled(
                      iconSize: 32,
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      onPressed: _at == null && !_playing ? null : (_playing ? _pause : _play),
                    ),
                    const SizedBox(width: 24),
                    _jump('+1m', const Duration(minutes: 1), color: Colors.white),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final DateTime? pos = _position;
    if (_full) return _fullScreen(pos);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('recording-hd'),
            tooltip: _hd ? 'SD' : 'HD',
            icon: Icon(_hd ? Icons.hd : Icons.sd),
            onPressed: () {
              setState(() => _hd = !_hd);
              if (_playing) {
                _pause();
                _play();
              }
            },
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: Stack(children: <Widget>[
                Positioned.fill(child: Center(child: _picture())),
                Positioned(
                  right: 0, bottom: 0,
                  child: IconButton(
                    key: const ValueKey<String>('recording-full'),
                    color: Colors.white,
                    tooltip: tr('fullScreen'),
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () => _setFull(true),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: <Widget>[
              Expanded(
                child: Text(pos == null ? '—' : clockText(pos),
                    key: const ValueKey<String>('recording-clock'),
                    style: const TextStyle(fontSize: 18, fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
              ),
              if (_ended) Text(tr('recordingsEnd'), style: const TextStyle(color: Colors.grey)),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DayTimeline(
              stretches: _stretches,
              day: _day,
              position: pos,
              onPick: (DateTime t) {
                _seek(t);
                if (!_playing) _play();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _jump('-15m', const Duration(minutes: -15)),
                _jump('-1m', const Duration(minutes: -1)),
                IconButton.filled(
                  key: const ValueKey<String>('recording-play'),
                  iconSize: 32,
                  tooltip: _playing ? tr('recordingsPause') : tr('recordingsPlay'),
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _at == null && !_playing ? null : (_playing ? _pause : _play),
                ),
                _jump('+1m', const Duration(minutes: 1)),
                _jump('+15m', const Duration(minutes: 15)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 12, runSpacing: 8, children: <Widget>[
              ActionChip(
                key: const ValueKey<String>('recording-day'),
                avatar: const Icon(Icons.calendar_today, size: 18),
                label: Text(_day == null ? '—' : clockText(_day!).split(' ').first),
                onPressed: _pickDay,
              ),
              ActionChip(
                key: const ValueKey<String>('recording-time'),
                avatar: const Icon(Icons.schedule, size: 18),
                label: Text(tr('recordingsPickTime')),
                onPressed: _pickTime,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _jump(String label, Duration by, {Color? color}) => TextButton(
        key: ValueKey<String>('recording-jump$label${color == null ? '' : '-full'}'),
        style: color == null ? null : TextButton.styleFrom(foregroundColor: color),
        onPressed: _position == null ? null : () => _seek(_position!.add(by)),
        child: Text(label),
      );
}

/// The day from 00:00 to 24:00: recorded stretches filled in (archive ones lighter), the
/// position as a line. Tap or drag to play from that moment.
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.stretches, required this.day, this.position, required this.onPick});
  final List<Stretch> stretches;
  final DateTime? day;
  final DateTime? position;
  final ValueChanged<DateTime> onPick;

  /// The moment at [fraction] (0..1) of the day.
  static DateTime at(DateTime day, double fraction) {
    final DateTime midnight = DateTime(day.year, day.month, day.day);
    return midnight.add(Duration(seconds: (fraction.clamp(0.0, 1.0) * 86399).round()));
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (BuildContext c, BoxConstraints box) {
        void pick(double dx) {
          if (day != null) onPick(at(day!, dx / box.maxWidth));
        }

        return Column(children: <Widget>[
          GestureDetector(
            key: const ValueKey<String>('recording-timeline'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) => pick(d.localPosition.dx),
            child: CustomPaint(
              size: Size(box.maxWidth, 36),
              painter: _TimelinePainter(stretches, day, position, fg),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <String>['0', '6', '12', '18', '24']
                .map((String h) => Text(h, style: const TextStyle(fontSize: 11, color: Colors.grey)))
                .toList(),
          ),
        ]);
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.stretches, this.day, this.position, this.color);
  final List<Stretch> stretches;
  final DateTime? day;
  final DateTime? position;
  final Color color;

  double _x(DateTime t, Size size) {
    final DateTime midnight = DateTime(day!.year, day!.month, day!.day);
    return (t.difference(midnight).inSeconds / 86400).clamp(0.0, 1.0) * size.width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bar = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(bar, Paint()..color = Colors.grey.withValues(alpha: 0.2));
    if (day == null) return;
    for (final Stretch s in stretches) {
      final double l = _x(s.start, size), r = _x(s.end, size);
      canvas.drawRect(Rect.fromLTRB(l, 0, r < l + 1 ? l + 1 : r, size.height),
          Paint()..color = color.withValues(alpha: s.archive ? 0.45 : 0.85));
    }
    final DateTime? p = position;
    if (p != null && p.year == day!.year && p.month == day!.month && p.day == day!.day) {
      final double x = _x(p, size);
      canvas.drawRect(Rect.fromLTWH(x - 1, -2, 2, size.height + 4), Paint()..color = Colors.redAccent);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.stretches != stretches || old.day != day || old.position != position || old.color != color;
}
