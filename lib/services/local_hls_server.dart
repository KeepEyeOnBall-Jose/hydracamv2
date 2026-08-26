import "dart:async";
import "dart:io";

/// Serves a finalized local HLS bundle (`playlist.m3u8`, `init.mp4`, `.m4s`
/// chunks) over a loopback HTTP server so platform players that only accept
/// network HLS URIs (Android ExoPlayer via `video_player`) can replay a
/// recording stored on the device filesystem.
///
/// The server binds to `127.0.0.1` on an ephemeral port, only exposes files
/// inside [bundleDirectory], and supports HTTP range requests so segmented
/// fMP4 playback stays robust across players.
class LocalHlsServer {
  LocalHlsServer({
    required this.bundleDirectory,
    this.playlistName = "playlist.m3u8",
  });

  final Directory bundleDirectory;
  final String playlistName;

  HttpServer? _server;

  bool get isRunning => _server != null;

  /// The absolute, canonicalised directory the server is allowed to serve.
  late final String _rootPath =
      Directory(bundleDirectory.absolute.path).resolveSymbolicLinksSync();

  /// Starts the server and returns the playable playlist URL.
  Future<Uri> start() async {
    if (_server != null) {
      return playlistUrl;
    }
    if (!bundleDirectory.existsSync()) {
      throw StateError("HLS bundle directory does not exist: "
          "${bundleDirectory.path}");
    }
    final playlistFile = File("$_rootPath/$playlistName");
    if (!playlistFile.existsSync()) {
      throw StateError("HLS playlist not found: ${playlistFile.path}");
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(server.forEach(_handleRequest));
    return playlistUrl;
  }

  Uri get playlistUrl {
    final server = _server;
    if (server == null) {
      throw StateError("LocalHlsServer is not running.");
    }
    return Uri.http("127.0.0.1:${server.port}", "/$playlistName");
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final method = request.method;
      if (method != "GET" && method != "HEAD") {
        await _writeStatus(request, HttpStatus.methodNotAllowed);
        return;
      }

      final file = _resolveRequestedFile(request.uri.path);
      if (file == null || !file.existsSync()) {
        await _writeStatus(request, HttpStatus.notFound);
        return;
      }

      final length = await file.length();
      final response = request.response;
      response.headers.contentType = _contentTypeFor(file.path);
      response.headers.set(HttpHeaders.acceptRangesHeader, "bytes");
      response.headers.set(HttpHeaders.cacheControlHeader, "no-store");

      final range =
          _parseRange(request.headers.value(HttpHeaders.rangeHeader), length);
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          "bytes ${range.start}-${range.end}/$length",
        );
        response.headers.contentLength = range.length;
        if (method == "GET") {
          await response.addStream(
            file.openRead(range.start, range.end + 1),
          );
        }
      } else {
        response.statusCode = HttpStatus.ok;
        response.headers.contentLength = length;
        if (method == "GET") {
          await response.addStream(file.openRead());
        }
      }
      await response.close();
    } catch (_) {
      try {
        await _writeStatus(request, HttpStatus.internalServerError);
      } catch (_) {
        // Connection already gone; nothing else to do.
      }
    }
  }

  /// Resolves a request path to a file inside the served directory, rejecting
  /// any path that escapes the bundle root (path traversal guard).
  File? _resolveRequestedFile(String requestPath) {
    final decoded = Uri.decodeComponent(requestPath);
    final relative = decoded.startsWith("/") ? decoded.substring(1) : decoded;
    if (relative.isEmpty) {
      return File("$_rootPath/$playlistName");
    }
    final candidate = File("$_rootPath/$relative");
    final normalized = candidate.absolute.uri.normalizePath().toFilePath();
    final rootWithSep = _rootPath.endsWith(Platform.pathSeparator)
        ? _rootPath
        : "$_rootPath${Platform.pathSeparator}";
    if (!normalized.startsWith(rootWithSep)) {
      return null;
    }
    return File(normalized);
  }

  static ContentType _contentTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith(".m3u8")) {
      return ContentType("application", "vnd.apple.mpegurl");
    }
    if (lower.endsWith(".m4s")) {
      return ContentType("video", "iso.segment");
    }
    if (lower.endsWith(".mp4")) {
      return ContentType("video", "mp4");
    }
    return ContentType("application", "octet-stream");
  }

  static _ByteRange? _parseRange(String? headerValue, int length) {
    if (headerValue == null || !headerValue.startsWith("bytes=")) {
      return null;
    }
    final spec = headerValue.substring("bytes=".length).trim();
    if (spec.contains(",")) {
      return null; // Multi-range not supported; fall back to full body.
    }
    final dash = spec.indexOf("-");
    if (dash < 0) {
      return null;
    }
    final startText = spec.substring(0, dash).trim();
    final endText = spec.substring(dash + 1).trim();

    int start;
    int end;
    if (startText.isEmpty) {
      // Suffix range: last N bytes.
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0) {
        return null;
      }
      start = (length - suffix).clamp(0, length - 1);
      end = length - 1;
    } else {
      final parsedStart = int.tryParse(startText);
      if (parsedStart == null || parsedStart >= length) {
        return null;
      }
      start = parsedStart;
      end =
          endText.isEmpty ? length - 1 : (int.tryParse(endText) ?? length - 1);
      if (end >= length) {
        end = length - 1;
      }
    }
    if (end < start) {
      return null;
    }
    return _ByteRange(start, end);
  }

  static Future<void> _writeStatus(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
  }
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;
}
