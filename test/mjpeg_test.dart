import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/mjpeg.dart';

Uint8List jpeg(int n) => Uint8List.fromList(<int>[0xFF, 0xD8, ...List<int>.filled(30, n), 0xFF, 0xD9]);

void main() {
  test('frames across chunks, multipart headers ignored', () {
    final MjpegSplitter s = MjpegSplitter();
    final List<int> part1 = <int>[...'--frame\r\nContent-Type: image/jpeg\r\n\r\n'.codeUnits, ...jpeg(1).sublist(0, 10)];
    expect(s.add(part1), isEmpty);
    final List<Uint8List> out = s.add(<int>[...jpeg(1).sublist(10), ...'\r\n--frame\r\n\r\n'.codeUnits, ...jpeg(2)]);
    expect(out, <Uint8List>[jpeg(1), jpeg(2)]);
  });

  test('a lone FF at a chunk end waits for the next byte', () {
    final MjpegSplitter s = MjpegSplitter();
    final Uint8List j = jpeg(3);
    expect(s.add(j.sublist(0, j.length - 1)), isEmpty);
    expect(s.add(j.sublist(j.length - 1)), <Uint8List>[j]);
  });

  test('the stream yields only the newest frame of a chunk', () async {
    final StreamController<List<int>> c = StreamController<List<int>>();
    final Future<List<Uint8List>> got = mjpegFrames(c.stream).toList();
    c.add(<int>[...jpeg(1), ...jpeg(2)]);
    c.add(jpeg(3));
    await c.close();
    expect(await got, <Uint8List>[jpeg(2), jpeg(3)]);
  });
}
