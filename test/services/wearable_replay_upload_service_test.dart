import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/services/wearable_replay_upload_service.dart";

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      "hydracam_wearable_upload_test",
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test("upload posts wearable replay sidecars and POV media", () async {
    final trackFile = File("${tempDir.path}/watch-track.json")
      ..writeAsStringSync("{}");
    final sampleFile = File("${tempDir.path}/watch-track-chunk-0000.jsonl")
      ..writeAsStringSync("{}\n");
    final calibrationFile = File("${tempDir.path}/clap-flash-1.json")
      ..writeAsStringSync("{}");
    final markerFile = File("${tempDir.path}/marker-1.json")
      ..writeAsStringSync("{}");
    final povRecordingFile = File("${tempDir.path}/pov-1.json")
      ..writeAsStringSync("{}");
    final povMediaFile = File("${tempDir.path}/pov-1.mp4")
      ..writeAsBytesSync([0, 1, 2, 3]);
    final feedbackFile = File("${tempDir.path}/feedback-1.json")
      ..writeAsStringSync("{}");
    final manifestFile = File("${tempDir.path}/wearable-upload-manifest.json")
      ..writeAsStringSync(jsonEncode({
        "manifestVersion": 1,
        "sessionGuid": "session-1",
        "generatedAt": "2026-06-22T12:00:00.000Z",
        "trackFiles": [trackFile.path],
        "sampleFiles": [sampleFile.path],
        "calibrationFiles": [calibrationFile.path],
        "markerFiles": [markerFile.path],
        "povRecordingFiles": [povRecordingFile.path],
        "povMediaFiles": [povMediaFile.path],
        "feedbackFiles": [feedbackFile.path],
        "mediaTimelineIntent": {
          "registerPovAsReplayAngle": true,
          "renderAudioOnByDefault": true,
          "renderHeartRateOverlay": true,
          "renderMotionOverlay": true,
          "requirePrePublishReview": true,
        },
      }));

    Uri? capturedUri;
    Map<String, String>? capturedFields;
    List<String>? capturedFileFields;

    final service = WearableReplayUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        expect(request, isA<http.MultipartRequest>());
        final multipart = request as http.MultipartRequest;
        capturedUri = request.url;
        capturedFields = multipart.fields;
        capturedFileFields = multipart.files
            .map((file) =>
                "${file.field}:${file.filename}:${file.contentType.mimeType}")
            .toList();
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            """{"eventId":"hydracam-session-1","sessionGuid":"session-1","trackCount":1,"sampleFileCount":1,"calibrationCount":1,"markerCount":1,"povRecordingCount":1,"povMediaCount":1,"feedbackCount":1}"""
                .codeUnits,
          ]),
          200,
          headers: {"content-type": "application/json"},
        );
      }),
    );

    final result = await service.uploadManifest(
      sessionGuid: "session-1",
      manifestFile: manifestFile,
      pairedHydraCamDeviceId: "phone-1",
      participantId: "player-1",
    );

    expect(result.eventId, "hydracam-session-1");
    expect(result.sessionGuid, "session-1");
    expect(result.trackCount, 1);
    expect(result.sampleFileCount, 1);
    expect(result.calibrationCount, 1);
    expect(result.markerCount, 1);
    expect(result.povRecordingCount, 1);
    expect(result.povMediaCount, 1);
    expect(result.feedbackCount, 1);
    expect(
      capturedUri.toString(),
      "http://127.0.0.1:3010/api/hydracam-bridge/compat/sessions/upload-wearables?sessionGuid=session-1",
    );
    expect(capturedFields, containsPair("pairedHydraCamDeviceId", "phone-1"));
    expect(capturedFields, containsPair("participantId", "player-1"));
    final capturedManifest = jsonDecode(
      capturedFields!["manifestJson"]!,
    ) as Map<String, dynamic>;
    expect(capturedManifest["povMediaFiles"], [povMediaFile.path]);
    expect(capturedFileFields, [
      "trackFiles:watch-track.json:application/json",
      "sampleFiles:watch-track-chunk-0000.jsonl:application/x-ndjson",
      "calibrationFiles:clap-flash-1.json:application/json",
      "markerFiles:marker-1.json:application/json",
      "povRecordingFiles:pov-1.json:application/json",
      "povMediaFiles:pov-1.mp4:video/mp4",
      "feedbackFiles:feedback-1.json:application/json",
    ]);
  });

  test("upload ignores blank and non-string manifest sidecar entries",
      () async {
    final trackFile = File("${tempDir.path}/watch-track.json")
      ..writeAsStringSync("{}");
    final manifestFile = File("${tempDir.path}/wearable-upload-manifest.json")
      ..writeAsStringSync(jsonEncode({
        "manifestVersion": 1,
        "sessionGuid": "session-1",
        "generatedAt": "2026-06-22T12:00:00.000Z",
        "trackFiles": [
          "",
          "   ",
          123,
          null,
          trackFile.path,
        ],
        "sampleFiles": "not-a-list",
        "calibrationFiles": <String>[],
        "markerFiles": <String>[],
        "povRecordingFiles": <String>[],
        "povMediaFiles": <String>[],
        "feedbackFiles": <String>[],
      }));

    List<String>? capturedFileFields;

    final service = WearableReplayUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        final multipart = request as http.MultipartRequest;
        capturedFileFields = multipart.files
            .map((file) =>
                "${file.field}:${file.filename}:${file.contentType.mimeType}")
            .toList();
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            """{"eventId":"hydracam-session-1","sessionGuid":"session-1"}"""
                .codeUnits,
          ]),
          200,
          headers: {"content-type": "application/json"},
        );
      }),
    );

    final result = await service.uploadManifest(
      sessionGuid: "session-1",
      manifestFile: manifestFile,
      pairedHydraCamDeviceId: "phone-1",
      participantId: "player-1",
    );

    expect(result.eventId, "hydracam-session-1");
    expect(capturedFileFields, [
      "trackFiles:watch-track.json:application/json",
    ]);
  });

  test("upload surfaces non-2xx media-timeline bridge failures", () async {
    final manifestFile = File("${tempDir.path}/wearable-upload-manifest.json")
      ..writeAsStringSync(jsonEncode({
        "manifestVersion": 1,
        "sessionGuid": "session-1",
        "generatedAt": "2026-06-22T12:00:00.000Z",
        "trackFiles": <String>[],
        "sampleFiles": <String>[],
        "calibrationFiles": <String>[],
        "markerFiles": <String>[],
        "povRecordingFiles": <String>[],
        "povMediaFiles": <String>[],
        "feedbackFiles": <String>[],
      }));
    final service = WearableReplayUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(["unavailable".codeUnits]),
          503,
        );
      }),
    );

    await expectLater(
      service.uploadManifest(
        sessionGuid: "session-1",
        manifestFile: manifestFile,
        pairedHydraCamDeviceId: "phone-1",
        participantId: "player-1",
      ),
      throwsA(isA<HttpException>()),
    );
  });

  test("upload rejects successful bridge responses without identity fields",
      () async {
    final manifestFile = File("${tempDir.path}/wearable-upload-manifest.json")
      ..writeAsStringSync(jsonEncode({
        "manifestVersion": 1,
        "sessionGuid": "session-1",
        "generatedAt": "2026-06-22T12:00:00.000Z",
        "trackFiles": <String>[],
        "sampleFiles": <String>[],
        "calibrationFiles": <String>[],
        "markerFiles": <String>[],
        "povRecordingFiles": <String>[],
        "povMediaFiles": <String>[],
        "feedbackFiles": <String>[],
      }));
    final service = WearableReplayUploadService(
      baseApiUrl: "http://127.0.0.1:3010/api",
      httpClient: MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(["""{"trackCount":1}""".codeUnits]),
          200,
          headers: {"content-type": "application/json"},
        );
      }),
    );

    await expectLater(
      service.uploadManifest(
        sessionGuid: "session-1",
        manifestFile: manifestFile,
        pairedHydraCamDeviceId: "phone-1",
        participantId: "player-1",
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
