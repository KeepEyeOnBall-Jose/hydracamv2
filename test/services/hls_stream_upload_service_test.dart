import "dart:io";
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/models/hls_stream_bundle.dart";
import "package:hydracam/services/hls_stream_upload_service.dart";

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync("hydracam_hls_upload_test");
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test("upload posts a fixed-camera HLS bundle to media-timeline bridge",
      () async {
    File("${tempDir.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
squash-court-a-00000000.m4s
""");
    File("${tempDir.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
    File("${tempDir.path}/squash-court-a-00000000.m4s")
        .writeAsBytesSync([1, 2, 3]);
    final bundle = await HlsStreamBundle.fromDirectory(tempDir);

    Uri? capturedUri;
    Map<String, String>? capturedFields;
    List<String>? capturedFileFields;

    final service = HlsStreamUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        expect(request, isA<http.MultipartRequest>());
        final multipart = request as http.MultipartRequest;
        capturedUri = request.url;
        capturedFields = multipart.fields;
        capturedFileFields = multipart.files
            .map((file) => "${file.field}:${file.filename}")
            .toList();
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            """{"eventId":"hydracam-session-1","sessionGuid":"session-1","stream":{"fileId":"file-hls-0","filename":"playlist.m3u8","chunks":[]}}"""
                .codeUnits,
          ]),
          200,
          headers: {"content-type": "application/json"},
        );
      }),
    );

    final result = await service.uploadBundle(
      sessionGuid: "session-1",
      bundle: bundle,
      deviceId: "fixed-court-a",
      capturedAt: DateTime.utc(2026, 6, 19, 10),
      recordingId: "game-1-camera-a",
    );

    expect(result.fileId, "file-hls-0");
    expect(
      capturedUri.toString(),
      "http://127.0.0.1:3010/api/hydracam-bridge/compat/sessions/upload-hls?sessionGuid=session-1",
    );
    expect(capturedFields, containsPair("deviceId", "fixed-court-a"));
    expect(capturedFields, containsPair("recordingId", "game-1-camera-a"));
    expect(
        capturedFields, containsPair("capturedAt", "2026-06-19T10:00:00.000Z"));
    expect(capturedFields, containsPair("targetDurationSeconds", "2"));
    expect(capturedFileFields, [
      "playlist:playlist.m3u8",
      "init:init.mp4",
      "chunks:squash-court-a-00000000.m4s",
    ]);
  });

  test("upload includes native timing metadata when provided", () async {
    File("${tempDir.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
squash-court-a-00000000.m4s
""");
    File("${tempDir.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
    File("${tempDir.path}/squash-court-a-00000000.m4s")
        .writeAsBytesSync([1, 2, 3]);
    final bundle = await HlsStreamBundle.fromDirectory(tempDir);

    Map<String, String>? capturedFields;
    final service = HlsStreamUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        final multipart = request as http.MultipartRequest;
        capturedFields = multipart.fields;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            """{"eventId":"hydracam-session-1","sessionGuid":"session-1","stream":{"fileId":"file-hls-0","filename":"playlist.m3u8","chunks":[]}}"""
                .codeUnits,
          ]),
          200,
          headers: {"content-type": "application/json"},
        );
      }),
    );

    await service.uploadBundle(
      sessionGuid: "session-1",
      bundle: bundle,
      deviceId: "fixed-court-a",
      capturedAt: DateTime.utc(2026, 6, 19, 10),
      timingMetadata: const HlsStreamTimingMetadata(
        syncConfidence: "green",
        videoTimeZeroSharedClockNanos: 123456789,
        cameraTiming: {
          "sensorTimestampSource": "REALTIME",
          "timestampConfidence": "strict",
        },
        ntp: {
          "server": "pool.ntp.org",
          "confidence": "green",
        },
      ),
    );

    final raw = capturedFields?["nativeTimingMetadataJson"];
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded["syncConfidence"], "green");
    expect(decoded["videoTimeZeroSharedClockNanos"], 123456789);
    expect(decoded["cameraTiming"], {
      "sensorTimestampSource": "REALTIME",
      "timestampConfidence": "strict",
    });
    expect(decoded["ntp"], {
      "server": "pool.ntp.org",
      "confidence": "green",
    });
  });

  test("upload passes raw native timing metadata through unchanged", () async {
    File("${tempDir.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
squash-court-a-00000000.m4s
""");
    File("${tempDir.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
    File("${tempDir.path}/squash-court-a-00000000.m4s")
        .writeAsBytesSync([1, 2, 3]);
    final bundle = await HlsStreamBundle.fromDirectory(tempDir);

    Map<String, String>? capturedFields;
    final service = HlsStreamUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        final multipart = request as http.MultipartRequest;
        capturedFields = multipart.fields;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            """{"eventId":"hydracam-session-1","sessionGuid":"session-1","stream":{"fileId":"file-hls-0","filename":"playlist.m3u8","chunks":[]}}"""
                .codeUnits,
          ]),
          200,
          headers: {"content-type": "application/json"},
        );
      }),
    );

    const rawTimingMetadata =
        "{\"recorderMode\":\"synthetic_local\",\"chunkCount\":2}";
    await service.uploadBundle(
      sessionGuid: "session-1",
      bundle: bundle,
      deviceId: "fixed-court-a",
      capturedAt: DateTime.utc(2026, 6, 19, 10),
      timingMetadata: const HlsStreamTimingMetadata.rawJson(
        rawTimingMetadata,
      ),
    );

    expect(capturedFields?["nativeTimingMetadataJson"], rawTimingMetadata);
  });
}
