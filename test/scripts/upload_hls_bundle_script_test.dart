import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync("hydracam_hls_script_test");
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test("upload_hls_bundle retries a transient bridge failure", () async {
    _createBundle(tempDir);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var attempts = 0;
    final serverDone = Completer<void>();

    unawaited(() async {
      await for (final request in server) {
        attempts += 1;
        await request.drain<void>();
        if (attempts == 1) {
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..write("bridge warming");
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            "eventId": "script-event",
            "sessionGuid": "script-session",
            "stream": {
              "fileId": "playlist-file-script",
              "filename": "playlist.m3u8",
              "chunks": [],
            },
          }));
        }
        await request.response.close();
        if (attempts >= 2 && !serverDone.isCompleted) {
          serverDone.complete();
          await server.close(force: true);
          break;
        }
      }
    }());

    try {
      final result = await Process.run(
          "dart",
          [
            "run",
            "scripts/upload_hls_bundle.dart",
            "--directory",
            tempDir.path,
            "--session-guid",
            "script-session",
            "--device-id",
            "fixed-court-a",
            "--base-api-url",
            "http://${server.address.host}:${server.port}/api",
            "--recording-id",
            "game-1-camera-a",
            "--retry-delay-ms",
            "0",
          ],
          workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(attempts, 2);
      expect(result.stdout.toString(), contains("playlist-file-script"));
      await serverDone.future.timeout(const Duration(seconds: 2));
    } finally {
      if (!serverDone.isCompleted) {
        await server.close(force: true);
      }
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test("upload_hls_bundle sends raw native timing metadata when provided",
      () async {
    _createBundle(tempDir);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = Completer<void>();
    String? requestBody;

    unawaited(() async {
      await for (final request in server) {
        requestBody = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          "eventId": "script-event",
          "sessionGuid": "script-session",
          "stream": {
            "fileId": "playlist-file-script",
            "filename": "playlist.m3u8",
            "chunks": [],
          },
        }));
        await request.response.close();
        if (!serverDone.isCompleted) {
          serverDone.complete();
          await server.close(force: true);
          break;
        }
      }
    }());

    try {
      const rawTimingMetadata =
          "{\"recorderMode\":\"synthetic_local\",\"chunkCount\":1}";
      final result = await Process.run(
          "dart",
          [
            "run",
            "scripts/upload_hls_bundle.dart",
            "--directory",
            tempDir.path,
            "--session-guid",
            "script-session",
            "--device-id",
            "fixed-court-a",
            "--base-api-url",
            "http://${server.address.host}:${server.port}/api",
            "--recording-id",
            "game-1-camera-a",
            "--native-timing-metadata-json",
            rawTimingMetadata,
            "--retry-delay-ms",
            "0",
          ],
          workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await serverDone.future.timeout(const Duration(seconds: 2));
      expect(requestBody, contains('name="nativeTimingMetadataJson"'));
      expect(requestBody, contains(rawTimingMetadata));
    } finally {
      if (!serverDone.isCompleted) {
        await server.close(force: true);
      }
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

void _createBundle(Directory directory) {
  File("${directory.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
squash-court-a-00000000.m4s
""");
  File("${directory.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
  File("${directory.path}/squash-court-a-00000000.m4s")
      .writeAsBytesSync([1, 2, 3]);
}
