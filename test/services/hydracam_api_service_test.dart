import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:package_info_plus/package_info_plus.dart";

const List<int> _validJpegBytes = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const List<int> _validMp4Bytes = [
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x6d,
  0x70,
  0x34,
  0x32,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    M2MAuthService.overrideTokenForTests("test-token");
    PackageInfo.setMockInitialValues(
      appName: "HydraCam",
      packageName: "com.vectorblanco.hydracam.dev",
      version: "2.3.4",
      buildNumber: "567",
      buildSignature: "",
    );
    LogService.instance.clearLogs();
    tempDir = Directory.systemTemp.createTempSync("hydracam_api_test");
  });

  tearDown(() {
    HydraCamApiService.resetHttpClient();
    LogService.instance.clearLogs();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test("uploadMedia includes app version fields in multipart metadata",
      () async {
    final mediaFile = File("${tempDir.path}/photo.jpg")
      ..writeAsBytesSync(_validJpegBytes);
    Map<String, String>? capturedFields;

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        expect(request.method, "POST");
        expect(request, isA<http.MultipartRequest>());
        capturedFields = (request as http.MultipartRequest).fields;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      true,
      "slave-device",
      DateTime.utc(2026, 6, 8, 19),
      DateTime.utc(2026, 6, 8, 19, 0, 1),
      null,
    );

    expect(result, isTrue);
    expect(capturedFields, containsPair("appVersion", "2.3.4"));
    expect(capturedFields, containsPair("appBuildNumber", "567"));
  });

  test("uploadMedia includes video recording end and duration metadata",
      () async {
    final mediaFile = File("${tempDir.path}/video.mp4")
      ..writeAsBytesSync(_validMp4Bytes);
    Map<String, String>? capturedFields;

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        expect(request.method, "POST");
        expect(request, isA<http.MultipartRequest>());
        capturedFields = (request as http.MultipartRequest).fields;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final recordingStart = DateTime.utc(2026, 6, 8, 21, 45);
    final recordingEnd = recordingStart.add(const Duration(seconds: 42));

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      recordingStart,
      recordingEnd.add(const Duration(milliseconds: 250)),
      null,
      recordingEndDate: recordingEnd,
      recordingDuration: recordingEnd.difference(recordingStart),
    );

    expect(result, isTrue);
    expect(
      capturedFields,
      containsPair("recordingEndDate", recordingEnd.toIso8601String()),
    );
    expect(capturedFields, containsPair("durationMs", "42000"));
  });

  test("uploadMedia derives duration from recording timestamps when mismatched",
      () async {
    final mediaFile = File("${tempDir.path}/video-timestamp-duration.mp4")
      ..writeAsBytesSync(_validMp4Bytes);
    Map<String, String>? capturedFields;

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        capturedFields = (request as http.MultipartRequest).fields;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final recordingStart = DateTime.utc(2026, 6, 17, 19, 10);
    final recordingEnd = recordingStart.add(const Duration(seconds: 42));

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      recordingStart,
      recordingEnd.add(const Duration(milliseconds: 500)),
      null,
      recordingEndDate: recordingEnd,
      recordingDuration: const Duration(seconds: 357),
    );

    expect(result, isTrue);
    expect(capturedFields, containsPair("durationMs", "42000"));
  });

  test("uploadMedia rejects inverted video recording timestamps", () async {
    final mediaFile = File("${tempDir.path}/video-inverted-duration.mp4")
      ..writeAsBytesSync(_validMp4Bytes);
    var requestSent = false;

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        requestSent = true;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final recordingStart = DateTime.utc(2026, 6, 17, 19, 20);
    final recordingEnd = recordingStart.subtract(const Duration(seconds: 1));

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      recordingStart,
      recordingStart.add(const Duration(milliseconds: 500)),
      null,
      recordingEndDate: recordingEnd,
      recordingDuration: recordingEnd.difference(recordingStart),
    );

    expect(result, isFalse);
    expect(requestSent, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      isNot(contains("Get token")),
    );
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(
        "Upload video duration is invalid: recordingEndDate is before captureDate for ${mediaFile.path}",
      ),
    );
  });

  test("uploadMedia uses centralized upload-media contract fields", () async {
    final mediaFile = File("${tempDir.path}/contract-video.mp4")
      ..writeAsBytesSync(_validMp4Bytes);
    Uri? capturedUri;
    Map<String, String>? capturedFields;
    List<http.MultipartFile>? capturedFiles;

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        expect(request.method, HydraCamUploadMediaContract.method);
        expect(request, isA<http.MultipartRequest>());
        final multipartRequest = request as http.MultipartRequest;
        capturedUri = request.url;
        capturedFields = multipartRequest.fields;
        capturedFiles = multipartRequest.files;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          HydraCamUploadMediaContract.successStatusCode,
        );
      }),
    );

    final recordingStart = DateTime.utc(2026, 6, 8, 22, 27);
    final recordingEnd = recordingStart.add(const Duration(seconds: 9));

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      recordingStart,
      recordingEnd,
      null,
      recordingEndDate: recordingEnd,
      recordingDuration: recordingEnd.difference(recordingStart),
    );

    expect(result, isTrue);
    expect(
      capturedUri?.path,
      "/api/${HydraCamUploadMediaContract.endpoint}",
    );
    expect(
      capturedUri?.queryParameters,
      containsPair(
          HydraCamUploadMediaContract.querySessionGuid, "session-guid"),
    );
    expect(
      capturedUri?.queryParameters,
      containsPair(HydraCamUploadMediaContract.queryIsPhoto, "false"),
    );
    expect(
      capturedFields,
      containsPair(
          HydraCamUploadMediaContract.fieldSlaveDeviceId, "slave-device"),
    );
    expect(
      capturedFields,
      containsPair(
        HydraCamUploadMediaContract.fieldCaptureDate,
        recordingStart.toIso8601String(),
      ),
    );
    expect(
      capturedFields,
      containsPair(
        HydraCamUploadMediaContract.fieldReceivedDate,
        recordingEnd.toIso8601String(),
      ),
    );
    expect(
      capturedFields,
      containsPair(
        HydraCamUploadMediaContract.fieldRecordingEndDate,
        recordingEnd.toIso8601String(),
      ),
    );
    expect(
      capturedFields,
      containsPair(HydraCamUploadMediaContract.fieldDurationMs, "9000"),
    );
    expect(
      capturedFields,
      containsPair(HydraCamUploadMediaContract.fieldAppVersion, "2.3.4"),
    );
    expect(
      capturedFields,
      containsPair(HydraCamUploadMediaContract.fieldAppBuildNumber, "567"),
    );
    expect(capturedFiles?.single.field, HydraCamUploadMediaContract.fileField);
  });

  test("uploadMedia omits video duration metadata for photo uploads", () async {
    final mediaFile = File("${tempDir.path}/photo.jpg")
      ..writeAsBytesSync(_validJpegBytes);
    Map<String, String>? capturedFields;

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        capturedFields = (request as http.MultipartRequest).fields;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      true,
      "slave-device",
      DateTime.utc(2026, 6, 8, 21, 45),
      DateTime.utc(2026, 6, 8, 21, 45, 1),
      null,
    );

    expect(result, isTrue);
    expect(capturedFields?.containsKey("recordingEndDate"), isFalse);
    expect(capturedFields?.containsKey("durationMs"), isFalse);
  });

  test("createSession returns typed backend session from API response",
      () async {
    Uri? requestedUri;
    Map<String, dynamic>? requestBody;
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"guid":"backend-guid","sessionId":"friendly-session","id":42}',
          200,
        );
      }),
    );

    final result = await HydraCamApiService().createSession(
      "friendly-session",
      courtGuid: "court-guid",
      userGuid: "user-guid",
    );

    expect(result, isNotNull);
    expect(result?.guid, "backend-guid");
    expect(result?.sessionId, "friendly-session");
    expect(result?.numericId, 42);
    expect(requestedUri?.path, "/api/sessions/create");
    expect(
      requestedUri?.queryParameters,
      containsPair("courtGuid", "court-guid"),
    );
    expect(
      requestedUri?.queryParameters,
      containsPair("userGuid", "user-guid"),
    );
    expect(requestBody, containsPair("SessionId", "friendly-session"));
  });

  test("warmUpBackend sends an authenticated lightweight startup request",
      () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUri = request.url;
        requestedHeaders = request.headers;
        return http.Response("[]", 200);
      }),
    );

    final result = await HydraCamApiService().warmUpBackend();

    expect(result, isTrue);
    expect(requestedUri?.path, "/api/sportscenters");
    expect(
      requestedHeaders,
      containsPair("Authorization", "Bearer test-token"),
    );
  });

  test("uploadMedia rejects missing files before HTTP send", () async {
    var requestSent = false;
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        requestSent = true;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final missingFile = File("${tempDir.path}/missing-video.mp4");

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      missingFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 8, 22, 5),
      DateTime.utc(2026, 6, 8, 22, 5, 1),
      null,
    );

    expect(result, isFalse);
    expect(requestSent, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Upload file does not exist: ${missingFile.path}"),
    );
  });

  test("uploadMedia rejects empty files before HTTP send", () async {
    var requestSent = false;
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        requestSent = true;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final emptyFile = File("${tempDir.path}/empty-video.mp4")
      ..writeAsBytesSync([]);

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      emptyFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 9, 4, 30),
      DateTime.utc(2026, 6, 9, 4, 30, 1),
      null,
    );

    expect(result, isFalse);
    expect(requestSent, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Upload file is empty: ${emptyFile.path}"),
    );
  });

  test("uploadMedia rejects corrupt local photo and video before HTTP send",
      () async {
    var requestCount = 0;
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        requestCount += 1;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final corruptPhoto = File("${tempDir.path}/corrupt-photo.jpg")
      ..writeAsStringSync("this is not an image");
    final corruptVideo = File("${tempDir.path}/corrupt-video.mp4")
      ..writeAsStringSync("this is not a video");

    final photoResult = await HydraCamApiService().uploadMedia(
      "session-guid",
      corruptPhoto,
      true,
      "slave-device",
      DateTime.utc(2026, 6, 17, 16),
      DateTime.utc(2026, 6, 17, 16, 0, 1),
      null,
    );
    final videoResult = await HydraCamApiService().uploadMedia(
      "session-guid",
      corruptVideo,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 17, 16),
      DateTime.utc(2026, 6, 17, 16, 0, 1),
      null,
    );

    expect(photoResult, isFalse);
    expect(videoResult, isFalse);
    expect(requestCount, 0);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Upload file is not valid photo media: ${corruptPhoto.path}"),
    );
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Upload file is not valid video media: ${corruptVideo.path}"),
    );
  });

  test("uploadMedia rejects backend failure bodies with HTTP 200", () async {
    final mediaFile = File("${tempDir.path}/backend-rejected.mp4")
      ..writeAsBytesSync(_validMp4Bytes);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              jsonEncode({
                "success": false,
                "message": "Rejected corrupt media",
              }),
            ),
          ]),
          200,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 9, 5),
      DateTime.utc(2026, 6, 9, 5, 0, 1),
      null,
    );

    expect(result, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(
        'Failed to upload media: HTTP 200 backend response reported failure - {"success":false,"message":"Rejected corrupt media"}',
      ),
    );
  });

  test("uploadMedia accepts deployed legacy plaintext success body", () async {
    final mediaFile = File("${tempDir.path}/legacy-success-response.mp4")
      ..writeAsBytesSync(_validMp4Bytes);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode("Media uploaded successfully."),
          ]),
          200,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 17, 20),
      DateTime.utc(2026, 6, 17, 20, 0, 1),
      null,
    );

    expect(result, isTrue);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Media uploaded successfully"),
    );
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      isNot(contains(contains("backend response reported failure"))),
    );
  });

  test("uploadMedia accepts JSON success aliases", () async {
    final successBodies = [
      {"success": true},
      {"succeeded": true},
      {"isSuccess": true},
    ];

    for (var index = 0; index < successBodies.length; index += 1) {
      LogService.instance.clearLogs();
      final mediaFile = File("${tempDir.path}/json-success-$index.mp4")
        ..writeAsBytesSync(_validMp4Bytes);

      HydraCamApiService.configureHttpClient(
        MockClient.streaming((request, bodyStream) async {
          await bodyStream.drain<void>();
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode(jsonEncode(successBodies[index])),
            ]),
            200,
          );
        }),
      );

      final result = await HydraCamApiService().uploadMedia(
        "session-guid",
        mediaFile,
        false,
        "slave-device",
        DateTime.utc(2026, 6, 17, 20, 5, index),
        DateTime.utc(2026, 6, 17, 20, 5, index + 1),
        null,
      );

      expect(result, isTrue);
      expect(
        LogService.instance.logs.map((entry) => entry["message"]),
        contains("Media uploaded successfully"),
      );
    }
  });

  test("uploadMedia rejects textual false success aliases", () async {
    final failureBodies = [
      {"success": "false"},
      {"succeeded": "0"},
      {"isSuccess": "no"},
    ];

    for (var index = 0; index < failureBodies.length; index += 1) {
      LogService.instance.clearLogs();
      final mediaFile = File("${tempDir.path}/json-text-failure-$index.mp4")
        ..writeAsBytesSync(_validMp4Bytes);

      HydraCamApiService.configureHttpClient(
        MockClient.streaming((request, bodyStream) async {
          await bodyStream.drain<void>();
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode(jsonEncode(failureBodies[index])),
            ]),
            200,
          );
        }),
      );

      final result = await HydraCamApiService().uploadMedia(
        "session-guid",
        mediaFile,
        false,
        "slave-device",
        DateTime.utc(2026, 6, 18, 17, index),
        DateTime.utc(2026, 6, 18, 17, index, 1),
        null,
      );

      expect(result, isFalse);
      expect(
        LogService.instance.logs.map((entry) => entry["message"]),
        contains(
          "Failed to upload media: HTTP 200 backend response reported failure - ${jsonEncode(failureBodies[index])}",
        ),
      );
    }
  });

  test("uploadMedia rejects malformed backend success bodies", () async {
    final mediaFile = File("${tempDir.path}/malformed-response.mp4")
      ..writeAsBytesSync(_validMp4Bytes);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([utf8.encode("not-json")]),
          200,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 17, 15),
      DateTime.utc(2026, 6, 17, 15, 0, 1),
      null,
    );

    expect(result, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(
        "Failed to upload media: HTTP 200 backend response reported failure - not-json",
      ),
    );
  });

  test("uploadMedia bounds logged response bodies for failures", () async {
    final mediaFile = File("${tempDir.path}/large-failure-response.mp4")
      ..writeAsBytesSync(_validMp4Bytes);
    final largeBody = "backend failure ${List.filled(800, "x").join()}";

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([utf8.encode(largeBody)]),
          500,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 17, 20, 10),
      DateTime.utc(2026, 6, 17, 20, 10, 1),
      null,
    );

    final messages = LogService.instance.logs
        .map((entry) => entry["message"].toString())
        .toList();

    expect(result, isFalse);
    expect(messages, contains(contains("Failed to upload media: HTTP 500 - ")));
    expect(messages.join("\n"), isNot(contains(largeBody)));
    expect(messages.join("\n"), contains("..."));
  });

  test("uploadMedia rejects backend error objects with HTTP 200", () async {
    final mediaFile = File("${tempDir.path}/backend-error-object.mp4")
      ..writeAsBytesSync(_validMp4Bytes);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              jsonEncode({
                "error": "Unsupported media codec",
              }),
            ),
          ]),
          200,
        );
      }),
    );

    final result = await HydraCamApiService().uploadMedia(
      "session-guid",
      mediaFile,
      false,
      "slave-device",
      DateTime.utc(2026, 6, 17, 19),
      DateTime.utc(2026, 6, 17, 19, 0, 1),
      null,
    );

    expect(result, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(
        'Failed to upload media: HTTP 200 backend response reported failure - {"error":"Unsupported media codec"}',
      ),
    );
  });

  test("fetchCourts preserves encoded sports center query values", () async {
    Uri? requestedUri;
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUri = request.url;
        return http.Response("[]", 200);
      }),
    );

    final result = await HydraCamApiService().fetchCourts(
      sportsCenterGuid: "sports center/guid+one",
    );

    expect(result, isEmpty);
    expect(requestedUri?.path, "/api/courts");
    expect(
      requestedUri?.queryParameters,
      containsPair("sportsCenterGuid", "sports center/guid+one"),
    );
  });

  test("endSession preserves encoded session guid query values", () async {
    Uri? requestedUri;
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUri = request.url;
        return http.Response("{}", 200);
      }),
    );

    final result =
        await HydraCamApiService().endSession("session guid/one+two");

    expect(result, isTrue);
    expect(requestedUri?.path, "/api/sessions/end");
    expect(
      requestedUri?.queryParameters,
      containsPair("sessionGuid", "session guid/one+two"),
    );
  });

  test("deleteDebugSession sends service cleanup identifiers", () async {
    Uri? requestedUri;
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUri = request.url;
        return http.Response("{}", 200);
      }),
    );

    final result = await HydraCamApiService().deleteDebugSession(
      sessionGuid: "debug guid/one+two",
      serviceNumericId: 456,
    );

    expect(result, isTrue);
    expect(requestedUri?.path, "/api/sessions/debug/delete");
    expect(
      requestedUri?.queryParameters,
      containsPair("sessionGuid", "debug guid/one+two"),
    );
    expect(requestedUri?.queryParameters, containsPair("id", "456"));
  });

  test("user lookups use centralized user contract endpoints", () async {
    final requestedUris = <Uri>[];
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUris.add(request.url);
        if (request.url.path ==
            "/api/${HydraCamUserContract.getByEmailEndpoint}") {
          return http.Response('{"guid":"user-guid"}', 200);
        }
        if (request.url.path ==
            "/api/${hydracamUserDetailsEndpoint("user-guid")}") {
          return http.Response('{"displayName":"Player One"}', 200);
        }
        return http.Response("{}", 404);
      }),
    );

    final guid =
        await HydraCamApiService().getUserGuidByEmail("player+one@example.com");
    final details = await HydraCamApiService().fetchUserDetails("user-guid");

    expect(guid, "user-guid");
    expect(details, containsPair("displayName", "Player One"));
    expect(
      requestedUris.first.queryParameters,
      containsPair(
        HydraCamUserContract.queryEmail,
        "player+one@example.com",
      ),
    );
    expect(requestedUris, hasLength(2));
  });
}
