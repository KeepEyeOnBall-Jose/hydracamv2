import "dart:io";

class HlsStreamBundle {
  const HlsStreamBundle({
    required this.playlist,
    required this.chunks,
    this.initSegment,
    this.targetDuration,
  });

  final File playlist;
  final File? initSegment;
  final List<File> chunks;
  final Duration? targetDuration;

  int get totalBytes {
    final initBytes = initSegment?.lengthSync() ?? 0;
    final chunkBytes = chunks.fold<int>(
      0,
      (sum, chunk) => sum + chunk.lengthSync(),
    );
    return initBytes + chunkBytes;
  }

  static Future<HlsStreamBundle> fromDirectory(
    Directory directory, {
    String playlistName = "playlist.m3u8",
  }) async {
    final playlist = File("${directory.path}/$playlistName");
    if (!playlist.existsSync()) {
      throw StateError("HLS playlist not found: ${playlist.path}");
    }

    final lines = await playlist.readAsLines();
    final initUri = _parseInitSegmentUri(lines);
    final targetDuration = _parseTargetDuration(lines);
    final chunkUris = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith("#"))
        .toList(growable: false);

    final initSegment = initUri == null
        ? null
        : _resolvePlaylistFile(directory, initUri, "init segment");
    final chunks = chunkUris
        .map((uri) => _resolvePlaylistFile(directory, uri, "chunk"))
        .toList(growable: false);

    if (chunks.isEmpty) {
      throw StateError("HLS playlist does not reference any chunks.");
    }

    for (final file in [if (initSegment != null) initSegment, ...chunks]) {
      if (!file.existsSync()) {
        throw StateError("HLS playlist references missing file: ${file.path}");
      }
    }

    return HlsStreamBundle(
      playlist: playlist,
      initSegment: initSegment,
      chunks: chunks,
      targetDuration: targetDuration,
    );
  }

  static String? _parseInitSegmentUri(List<String> lines) {
    final initLine = lines
        .map((line) => line.trim())
        .where((line) => line.startsWith("#EXT-X-MAP:"))
        .firstOrNull;
    if (initLine == null) return null;
    final match = RegExp("URI=\"([^\"]+)\"").firstMatch(initLine);
    return match?.group(1);
  }

  static Duration? _parseTargetDuration(List<String> lines) {
    final targetLine = lines
        .map((line) => line.trim())
        .where((line) => line.startsWith("#EXT-X-TARGETDURATION:"))
        .firstOrNull;
    if (targetLine == null) return null;
    final raw = targetLine.split(":").last.trim();
    final seconds = int.tryParse(raw);
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static File _resolvePlaylistFile(
    Directory directory,
    String rawUri,
    String label,
  ) {
    final uri = Uri.parse(rawUri.trim());
    if (uri.hasScheme || uri.hasAuthority) {
      throw StateError("HLS $label must be a local relative URI: $rawUri");
    }
    return File.fromUri(directory.uri.resolve(uri.path));
  }
}
