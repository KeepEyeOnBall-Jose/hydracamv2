import "dart:math";

class HlsPlaylistSegment {
  const HlsPlaylistSegment({
    required this.fileName,
    required this.duration,
  });

  final String fileName;
  final Duration duration;
}

class HlsPlaylistManifest {
  const HlsPlaylistManifest({
    required this.initFileName,
    required this.segments,
    this.isFinal = false,
  });

  final String initFileName;
  final List<HlsPlaylistSegment> segments;
  final bool isFinal;

  String render() {
    final targetDurationSeconds = max(
      1,
      segments
          .map((segment) =>
              segment.duration.inMicroseconds / Duration.microsecondsPerSecond)
          .fold<double>(0, max)
          .ceil(),
    );
    final buffer = StringBuffer()
      ..writeln("#EXTM3U")
      ..writeln("#EXT-X-VERSION:7")
      ..writeln("#EXT-X-TARGETDURATION:$targetDurationSeconds")
      ..writeln("#EXT-X-MEDIA-SEQUENCE:0")
      ..writeln("#EXT-X-INDEPENDENT-SEGMENTS")
      ..writeln("#EXT-X-MAP:URI=\"$initFileName\"");

    for (final segment in segments) {
      final seconds =
          segment.duration.inMicroseconds / Duration.microsecondsPerSecond;
      buffer
        ..writeln("#EXTINF:${seconds.toStringAsFixed(3)},")
        ..writeln(segment.fileName);
    }
    if (isFinal) {
      buffer.writeln("#EXT-X-ENDLIST");
    }
    return buffer.toString();
  }

  static String chunkFileName({
    required String deviceId,
    required String streamId,
    required int chunkNumber,
  }) {
    if (chunkNumber < 0) {
      throw ArgumentError.value(chunkNumber, "chunkNumber", "must be >= 0");
    }
    final padded = chunkNumber.toString().padLeft(8, "0");
    return "$deviceId-$streamId-$padded.m4s";
  }
}
