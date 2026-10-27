import 'dart:typed_data';

// The camera's live feed (gateway GET /cameras/{id}/live, owner 2026-10-27: "should be real
// time") is MJPEG: one JPEG after another. Frames are cut at the JPEG start/end markers
// (FF D8 ... FF D9), so the multipart headers between them need no parsing.

class MjpegSplitter {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  /// Feeds a chunk; returns the complete frames it finished, oldest first.
  List<Uint8List> add(List<int> chunk) {
    _buf.add(chunk);
    Uint8List data = _buf.takeBytes();
    final List<Uint8List> out = <Uint8List>[];
    int pos = 0;
    while (true) {
      final int start = _find(data, 0xD8, pos);
      if (start < 0) { pos = data.length; break; }
      final int end = _find(data, 0xD9, start + 2);
      if (end < 0) { pos = start; break; }
      out.add(Uint8List.sublistView(data, start, end + 2));
      pos = end + 2;
    }
    if (pos < data.length) _buf.add(Uint8List.sublistView(data, pos));
    // Copies, so the frames do not pin the whole chunk.
    return out.map(Uint8List.fromList).toList();
  }

  static int _find(Uint8List d, int second, int from) {
    for (int i = from; i + 1 < d.length; i++) {
      if (d[i] == 0xFF && d[i + 1] == second) return i;
    }
    return -1;
  }
}

/// Frames from a byte stream; only the newest matters, so a slow listener just skips.
Stream<Uint8List> mjpegFrames(Stream<List<int>> bytes) async* {
  final MjpegSplitter s = MjpegSplitter();
  await for (final List<int> chunk in bytes) {
    final List<Uint8List> frames = s.add(chunk);
    if (frames.isNotEmpty) yield frames.last;
  }
}
