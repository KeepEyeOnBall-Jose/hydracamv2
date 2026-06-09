import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:package_info_plus/package_info_plus.dart";

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
      ..writeAsBytesSync([1, 2, 3, 4]);
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
      ..writeAsBytesSync([1, 2, 3, 4, 5, 6]);
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

  test("uploadMedia uses centralized upload-media contract fields", () async {
    final mediaFile = File("${tempDir.path}/contract-video.mp4")
      ..writeAsBytesSync([1, 2, 3, 4, 5, 6]);
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
      ..writeAsBytesSync([1, 2, 3, 4]);
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

  test("uploadMedia rejects backend failure bodies with HTTP 200", () async {
    final mediaFile = File("${tempDir.path}/backend-rejected.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);

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
        'Failed to upload media: backend response reported failure - {"success":false,"message":"Rejected corrupt media"}',
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
