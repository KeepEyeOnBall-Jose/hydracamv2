import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/local_hls_server.dart";

void main() {
  late Directory bundleDir;
  late LocalHlsServer server;

  setUp(() async {
    bundleDir = await Directory.systemTemp.createTemp("hls_server_test");
    File("${bundleDir.path}/playlist.m3u8").writeAsStringSync(
      "#EXTM3U\n"
      "#EXT-X-VERSION:7\n"
      "#EXT-X-TARGETDURATION:2\n"
      "#EXT-X-MAP:URI=\"init.mp4\"\n"
      "#EXTINF:2.0,\n"
      "chunk-00000000.m4s\n"
      "#EXT-X-ENDLIST\n",
    );
    File("${bundleDir.path}/init.mp4").writeAsBytesSync(
      List<int>.generate(64, (i) => i % 256),
    );
    File("${bundleDir.path}/chunk-00000000.m4s").writeAsBytesSync(
      List<int>.generate(2048, (i) => i % 256),
    );
    server = LocalHlsServer(bundleDirectory: bundleDir);
  });

  tearDown(() async {
    await server.stop();
    if (bundleDir.existsSync()) {
      bundleDir.deleteSync(recursive: true);
    }
  });

  Future<HttpClientResponse> get(Uri url, {String? range}) async {
    final client = HttpClient();
    final request = await client.getUrl(url);
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final response = await request.close();
    return response;
  }

  test("serves the playlist with the HLS content type", () async {
    final playlistUrl = await server.start();
    expect(playlistUrl.path, "/playlist.m3u8");

    final response = await get(playlistUrl);
    expect(response.statusCode, HttpStatus.ok);
    expect(
      response.headers.contentType.toString(),
      contains("application/vnd.apple.mpegurl"),
    );
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), "bytes");
    final body = await response.transform(utf8.decoder).join();
    expect(body, contains("#EXT-X-MAP:URI=\"init.mp4\""));
  });

  test("serves init segment and chunk referenced by the playlist", () async {
    final base = await server.start();

    final initResponse = await get(base.replace(path: "/init.mp4"));
    expect(initResponse.statusCode, HttpStatus.ok);
    expect(initResponse.headers.contentType.toString(), contains("video/mp4"));
    final initBytes = await _collect(initResponse);
    expect(initBytes.length, 64);

    final chunkResponse = await get(base.replace(path: "/chunk-00000000.m4s"));
    expect(chunkResponse.statusCode, HttpStatus.ok);
    expect(
      chunkResponse.headers.contentType.toString(),
      contains("video/iso.segment"),
    );
    final chunkBytes = await _collect(chunkResponse);
    expect(chunkBytes.length, 2048);
  });

  test("supports byte-range requests with 206 partial content", () async {
    final base = await server.start();
    final response = await get(base.replace(path: "/chunk-00000000.m4s"),
        range: "bytes=0-99");
    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      "bytes 0-99/2048",
    );
    final bytes = await _collect(response);
    expect(bytes.length, 100);
  });

  test("returns 404 for files not in the bundle", () async {
    final base = await server.start();
    final response = await get(base.replace(path: "/missing.m4s"));
    expect(response.statusCode, HttpStatus.notFound);
  });

  test("rejects path traversal outside the bundle root", () async {
    final base = await server.start();
    // A sibling secret file next to (but outside) the bundle directory.
    final secret = File("${bundleDir.parent.path}/secret.txt")
      ..writeAsStringSync("top secret");
    addTearDown(() {
      if (secret.existsSync()) secret.deleteSync();
    });

    final response = await get(
      base.replace(path: "/${Uri.encodeComponent("../secret.txt")}"),
    );
    expect(
        response.statusCode, anyOf(HttpStatus.notFound, HttpStatus.forbidden));
  });
}

Future<List<int>> _collect(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
  }
  return bytes;
}
