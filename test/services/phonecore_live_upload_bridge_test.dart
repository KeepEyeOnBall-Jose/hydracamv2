import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/screens/fixed_camera_hls_screen.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";
import "package:hydracam/services/phonecore_live_upload_bridge.dart";
import "package:hydracam/services/phonecore_live_upload_recovery.dart";
import "package:hydracam/services/phonecore_live_upload_service.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uploadChannel = MethodChannel(PhoneCoreLiveUploadService.channelName);
  const recorderChannel = MethodChannel(
    FixedCameraHlsRecorderService.channelName,
  );

  late Directory tempDir;
  late List<MethodCall> recordedCalls;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      "hydracam_phonecore_live_upload_bridge_test",
    );
    recordedCalls = <MethodCall>[];
    SharedPreferences.setMockInitialValues({"device_id": "fixed-court-a"});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uploadChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorderChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File writeSegmentFile(String name, List<int> bytes) {
    final file = File("${tempDir.path}/$name");
    file.writeAsBytesSync(bytes);
    return file;
  }

  String expectedSha256(List<int> bytes) => sha256.convert(bytes).toString();

  Map<String, Object?> snapshotMap({
    required String sessionId,
    String slot = "A",
    List<String> grantedTiers = const ["proxy"],
    int stoppedAtMs = 0,
    int lastSeqProxy = -1,
    int lastSeqMaster = -1,
    String? manifestState,
    int totalSegments = 0,
    int activeSegments = 0,
    int verifiedSegments = 0,
    int heldSegments = 0,
    int failedSegments = 0,
    int conflictSegments = 0,
    int pendingBytes = 0,
    bool isComplete = false,
  }) {
    return {
      "sessionId": sessionId,
      "slot": slot,
      "grantedTiers": grantedTiers,
      "stoppedAtMs": stoppedAtMs,
      "lastSeqProxy": lastSeqProxy,
      "lastSeqMaster": lastSeqMaster,
      "manifestState": manifestState,
      "totalSegments": totalSegments,
      "activeSegments": activeSegments,
      "verifiedSegments": verifiedSegments,
      "heldSegments": heldSegments,
      "failedSegments": failedSegments,
      "conflictSegments": conflictSegments,
      "pendingBytes": pendingBytes,
      "isComplete": isComplete,
      "items": const <Map<String, Object?>>[],
    };
  }

  void mockUploadChannel(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uploadChannel, (call) {
      recordedCalls.add(call);
      return handler(call);
    });
  }

  group("PhoneCoreLiveUploadBridge", () {
    test(
      "uploads finalized segments in exact sequence with real SHA-256 and bounded drain",
      () async {
        final seg1Bytes = List<int>.generate(32, (i) => i);
        final seg2Bytes = List<int>.generate(48, (i) => (i * 3) & 0xff);
        final seg3Bytes = List<int>.generate(64, (i) => (i * 7 + 1) & 0xff);
        final seg1 = writeSegmentFile("chunk-0001.ts", seg1Bytes);
        final seg2 = writeSegmentFile("chunk-0002.ts", seg2Bytes);
        final seg3 = writeSegmentFile("chunk-0003.ts", seg3Bytes);

        final startedAt = DateTime.utc(2026, 11, 22, 1, 0, 0);
        final finalizedAt = DateTime.utc(2026, 11, 22, 1, 0, 5);
        final recording = FixedCameraHlsRecordingResult(
          recordingId: "rec-live-1",
          recordingDirectoryPath: tempDir.path,
          state: FixedCameraHlsRecordingState.finalized,
          playlistPath: "${tempDir.path}/playlist.m3u8",
          chunkPaths: [seg1.path, seg2.path, seg3.path],
          durationSeconds: 5.0,
          targetDurationSeconds: 2,
          startedAt: startedAt,
          finalizedAt: finalizedAt,
        );

        var enqueuedCount = 0;
        var drainCalls = 0;
        mockUploadChannel((call) async {
          switch (call.method) {
            case "startSession":
              final args = call.arguments as Map;
              expect(args["sessionId"], "live-session-1");
              expect(args["slot"], "A");
              expect(args["uploadGrant"], "grant.jwt.token");
              expect(args["ingestUrl"], "https://ingest.example.com");
              return snapshotMap(sessionId: "live-session-1", slot: "A");
            case "enqueueSegment":
              enqueuedCount += 1;
              return snapshotMap(
                sessionId: "live-session-1",
                slot: "A",
                lastSeqProxy: enqueuedCount,
                totalSegments: enqueuedCount,
                activeSegments: enqueuedCount,
              );
            case "markRecordingStopped":
              final args = call.arguments as Map;
              expect(args["sessionId"], "live-session-1");
              expect(
                args["stoppedAtMs"],
                finalizedAt.millisecondsSinceEpoch,
              );
              return snapshotMap(
                sessionId: "live-session-1",
                slot: "A",
                stoppedAtMs: finalizedAt.millisecondsSinceEpoch,
                lastSeqProxy: enqueuedCount,
                totalSegments: enqueuedCount,
                activeSegments: enqueuedCount,
              );
            case "drainOnce":
              drainCalls += 1;
              expect(call.arguments, {"maxSteps": 10});
              if (drainCalls == 1) {
                return {
                  "stepsTaken": 2,
                  "didWork": true,
                  "hasPendingWork": true,
                  "nextWakeAtMs": null,
                };
              }
              return {
                "stepsTaken": 2,
                "didWork": true,
                "hasPendingWork": false,
                "nextWakeAtMs": null,
              };
            case "getSnapshot":
              final complete = drainCalls >= 2;
              return snapshotMap(
                sessionId: "live-session-1",
                slot: "A",
                stoppedAtMs: finalizedAt.millisecondsSinceEpoch,
                lastSeqProxy: 3,
                manifestState: complete ? "complete" : null,
                totalSegments: 3,
                activeSegments: complete ? 0 : 1,
                verifiedSegments: complete ? 3 : 2,
                isComplete: complete,
              );
            default:
              fail("Unexpected method call: ${call.method}");
          }
        });

        final sleeps = <Duration>[];
        final bridge = PhoneCoreLiveUploadBridge(
          sleep: (duration) async => sleeps.add(duration),
          nowMs: () => 1700000000000,
        );
        const config = PhoneCoreLiveUploadConfig(
          uploadGrant: "grant.jwt.token",
          ingestUrl: "https://ingest.example.com",
          slot: "A",
          tier: "proxy",
          maxDrainStepsPerCall: 10,
          maxDrainIterations: 6,
          drainDelay: Duration(milliseconds: 100),
        );

        final result = await bridge.uploadFinalizedRecording(
          sessionId: "live-session-1",
          recording: recording,
          config: config,
        );

        expect(
          recordedCalls.map((c) => c.method).toList(),
          [
            "startSession",
            "enqueueSegment",
            "enqueueSegment",
            "enqueueSegment",
            "markRecordingStopped",
            "drainOnce",
            "getSnapshot",
            "drainOnce",
            "getSnapshot",
          ],
        );

        final enqueueCalls = recordedCalls
            .where((c) => c.method == "enqueueSegment")
            .map((c) => Map<String, Object?>.from(c.arguments as Map))
            .toList();
        expect(enqueueCalls, hasLength(3));
        expect(enqueueCalls.map((c) => c["seq"]).toList(), [1, 2, 3]);
        expect(enqueueCalls.map((c) => c["sha256"]).toList(), [
          expectedSha256(seg1Bytes),
          expectedSha256(seg2Bytes),
          expectedSha256(seg3Bytes),
        ]);
        expect(enqueueCalls.map((c) => c["durationMs"]).toList(), [
          1667,
          1667,
          1666,
        ]);
        expect(
          enqueueCalls.map((c) => c["mediaStartServerMs"]).toList(),
          [
            startedAt.millisecondsSinceEpoch,
            startedAt.millisecondsSinceEpoch + 1667,
            startedAt.millisecondsSinceEpoch + 3334,
          ],
        );
        for (final args in enqueueCalls) {
          expect(args["tier"], "proxy");
          expect(args["slot"], "A");
        }

        expect(sleeps, isEmpty);
        expect(result.sessionId, "live-session-1");
        expect(result.enqueuedSegments, 3);
        expect(result.drainIterations, 2);
        expect(result.totalDrainSteps, 4);
        expect(result.hasPendingWork, isFalse);
        expect(result.isComplete, isTrue);
        expect(result.verifiedSegments, 3);
        expect(result.totalSegments, 3);
        expect(result.activeSegments, 0);
        expect(result.failedSegments, 0);
        expect(result.manifestState, "complete");
      },
    );

    test(
      "derives positive durationMs and monotonic mediaStartServerMs when durationSeconds and timestamps are absent",
      () async {
        final seg1 = writeSegmentFile("a.ts", [1, 2, 3]);
        final seg2 = writeSegmentFile("b.ts", [4, 5, 6]);
        final recording = FixedCameraHlsRecordingResult(
          recordingId: "rec-fallback",
          recordingDirectoryPath: tempDir.path,
          state: FixedCameraHlsRecordingState.finalized,
          chunkPaths: [seg1.path, seg2.path],
          durationSeconds: 0.001,
        );

        mockUploadChannel((call) async {
          switch (call.method) {
            case "startSession":
            case "enqueueSegment":
            case "markRecordingStopped":
              return snapshotMap(
                sessionId: "live-fallback",
                totalSegments: 2,
              );
            case "drainOnce":
              return {
                "stepsTaken": 2,
                "didWork": true,
                "hasPendingWork": false,
                "nextWakeAtMs": null,
              };
            case "getSnapshot":
              return snapshotMap(
                sessionId: "live-fallback",
                totalSegments: 2,
                verifiedSegments: 2,
                manifestState: "complete",
                isComplete: true,
              );
            default:
              return null;
          }
        });

        final bridge = PhoneCoreLiveUploadBridge(
          nowMs: () => 1700000100000,
        );
        final result = await bridge.uploadFinalizedRecording(
          sessionId: "live-fallback",
          recording: recording,
          config: const PhoneCoreLiveUploadConfig(
            uploadGrant: "grant",
            ingestUrl: "https://ingest.example.com",
            drainDelay: Duration.zero,
          ),
        );

        final enqueueCalls = recordedCalls
            .where((c) => c.method == "enqueueSegment")
            .map((c) => Map<String, Object?>.from(c.arguments as Map))
            .toList();
        expect(enqueueCalls[0]["seq"], 1);
        expect(enqueueCalls[1]["seq"], 2);
        expect(enqueueCalls[0]["durationMs"] as int, greaterThan(0));
        expect(enqueueCalls[1]["durationMs"] as int, greaterThan(0));
        expect(
          enqueueCalls[1]["mediaStartServerMs"] as int,
          greaterThan(enqueueCalls[0]["mediaStartServerMs"] as int),
        );
        expect(result.isComplete, isTrue);
      },
    );

    test(
      "terminates drain loop as soon as snapshot.isComplete is true even when hasPendingWork stays true",
      () async {
        final seg = writeSegmentFile("s0.ts", [10, 20, 30]);
        final recording = FixedCameraHlsRecordingResult(
          recordingId: "rec-complete",
          recordingDirectoryPath: tempDir.path,
          state: FixedCameraHlsRecordingState.finalized,
          chunkPaths: [seg.path],
          durationSeconds: 2.0,
        );

        var drainCount = 0;
        mockUploadChannel((call) async {
          switch (call.method) {
            case "startSession":
            case "enqueueSegment":
            case "markRecordingStopped":
              return snapshotMap(sessionId: "live-early-stop");
            case "drainOnce":
              drainCount += 1;
              return {
                "stepsTaken": 1,
                "didWork": true,
                "hasPendingWork": true,
                "nextWakeAtMs": 1700000005000,
              };
            case "getSnapshot":
              final complete = drainCount >= 2;
              return snapshotMap(
                sessionId: "live-early-stop",
                manifestState: complete ? "complete" : null,
                totalSegments: 1,
                activeSegments: complete ? 0 : 1,
                verifiedSegments: complete ? 1 : 0,
                isComplete: complete,
              );
            default:
              return null;
          }
        });

        final bridge = PhoneCoreLiveUploadBridge();
        final result = await bridge.uploadFinalizedRecording(
          sessionId: "live-early-stop",
          recording: recording,
          config: const PhoneCoreLiveUploadConfig(
            uploadGrant: "grant",
            ingestUrl: "https://ingest.example.com",
            maxDrainIterations: 10,
            drainDelay: Duration.zero,
          ),
        );

        expect(drainCount, 2);
        expect(result.drainIterations, 2);
        expect(result.isComplete, isTrue);
        expect(result.hasPendingWork, isTrue);
        expect(recordedCalls.last.method, "getSnapshot");
      },
    );

    test(
      "terminates drain loop at maxDrainIterations when pending work never completes",
      () async {
        final seg = writeSegmentFile("stalled.ts", [9, 8, 7]);
        final recording = FixedCameraHlsRecordingResult(
          recordingId: "rec-bounded",
          recordingDirectoryPath: tempDir.path,
          state: FixedCameraHlsRecordingState.finalized,
          chunkPaths: [seg.path],
          durationSeconds: 3.0,
        );

        var drainCount = 0;
        mockUploadChannel((call) async {
          switch (call.method) {
            case "startSession":
            case "enqueueSegment":
            case "markRecordingStopped":
              return snapshotMap(
                sessionId: "live-bounded",
                totalSegments: 1,
                activeSegments: 1,
              );
            case "drainOnce":
              drainCount += 1;
              return {
                "stepsTaken": 0,
                "didWork": false,
                "hasPendingWork": true,
                "nextWakeAtMs": 1700000009000,
              };
            case "getSnapshot":
              return snapshotMap(
                sessionId: "live-bounded",
                totalSegments: 1,
                activeSegments: 1,
                verifiedSegments: 0,
                isComplete: false,
              );
            default:
              return null;
          }
        });

        final sleeps = <Duration>[];
        final bridge = PhoneCoreLiveUploadBridge(
          sleep: (duration) async => sleeps.add(duration),
        );
        final result = await bridge.uploadFinalizedRecording(
          sessionId: "live-bounded",
          recording: recording,
          config: const PhoneCoreLiveUploadConfig(
            uploadGrant: "grant",
            ingestUrl: "https://ingest.example.com",
            maxDrainIterations: 3,
            drainDelay: Duration(milliseconds: 50),
          ),
        );

        expect(drainCount, 3);
        expect(sleeps, [
          const Duration(milliseconds: 50),
          const Duration(milliseconds: 50),
        ]);
        expect(result.drainIterations, 3);
        expect(result.totalDrainSteps, 0);
        expect(result.isComplete, isFalse);
        expect(result.hasPendingWork, isTrue);
        expect(result.activeSegments, 1);
        expect(recordedCalls.last.method, "getSnapshot");
      },
    );

    test("throws ArgumentError when chunkPaths is empty", () async {
      mockUploadChannel((call) async => null);
      final bridge = PhoneCoreLiveUploadBridge();
      final recording = FixedCameraHlsRecordingResult(
        recordingId: "rec-empty",
        recordingDirectoryPath: tempDir.path,
        state: FixedCameraHlsRecordingState.finalized,
        chunkPaths: const [],
      );

      await expectLater(
        () => bridge.uploadFinalizedRecording(
          sessionId: "live-empty",
          recording: recording,
          config: const PhoneCoreLiveUploadConfig(
            uploadGrant: "grant",
            ingestUrl: "https://ingest.example.com",
          ),
        ),
        throwsArgumentError,
      );
      expect(recordedCalls, isEmpty);
    });

    test("throws StateError when recording is not finalized", () async {
      final seg = writeSegmentFile("part.ts", [1, 2]);
      mockUploadChannel((call) async => null);
      final bridge = PhoneCoreLiveUploadBridge();
      final recording = FixedCameraHlsRecordingResult(
        recordingId: "rec-active",
        recordingDirectoryPath: tempDir.path,
        state: FixedCameraHlsRecordingState.recording,
        chunkPaths: [seg.path],
      );

      await expectLater(
        () => bridge.uploadFinalizedRecording(
          sessionId: "live-active",
          recording: recording,
          config: const PhoneCoreLiveUploadConfig(
            uploadGrant: "grant",
            ingestUrl: "https://ingest.example.com",
          ),
        ),
        throwsStateError,
      );
      expect(recordedCalls, isEmpty);
    });

    test("throws FileSystemException cleanly when a segment file is missing",
        () async {
      final existing = writeSegmentFile("present.ts", [1, 2, 3]);
      final missingPath = "${tempDir.path}/missing.ts";
      mockUploadChannel((call) async => null);
      final bridge = PhoneCoreLiveUploadBridge();
      final recording = FixedCameraHlsRecordingResult(
        recordingId: "rec-missing-file",
        recordingDirectoryPath: tempDir.path,
        state: FixedCameraHlsRecordingState.finalized,
        chunkPaths: [existing.path, missingPath],
      );

      await expectLater(
        () => bridge.uploadFinalizedRecording(
          sessionId: "live-missing",
          recording: recording,
          config: const PhoneCoreLiveUploadConfig(
            uploadGrant: "grant",
            ingestUrl: "https://ingest.example.com",
          ),
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.path,
            "path",
            missingPath,
          ),
        ),
      );
      expect(recordedCalls, isEmpty);
    });

    test("validates config bounds and required inputs before channel calls",
        () async {
      final seg = writeSegmentFile("valid.ts", [1, 2, 3]);
      mockUploadChannel((call) async => null);
      final bridge = PhoneCoreLiveUploadBridge();
      final recording = FixedCameraHlsRecordingResult(
        recordingId: "rec-val",
        recordingDirectoryPath: tempDir.path,
        state: FixedCameraHlsRecordingState.finalized,
        chunkPaths: [seg.path],
      );

      Future<void> expectRejected(
        String sessionId,
        PhoneCoreLiveUploadConfig config,
      ) {
        return expectLater(
          () => bridge.uploadFinalizedRecording(
            sessionId: sessionId,
            recording: recording,
            config: config,
          ),
          throwsArgumentError,
        );
      }

      await expectRejected(
        "   ",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: "grant",
          ingestUrl: "https://ingest.example.com",
        ),
      );
      await expectRejected(
        "live-val",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: " ",
          ingestUrl: "https://ingest.example.com",
        ),
      );
      await expectRejected(
        "live-val",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: "grant",
          ingestUrl: " ",
        ),
      );
      await expectRejected(
        "live-val",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: "grant",
          ingestUrl: "https://ingest.example.com",
          slot: "",
        ),
      );
      await expectRejected(
        "live-val",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: "grant",
          ingestUrl: "https://ingest.example.com",
          tier: "invalid",
        ),
      );
      await expectRejected(
        "live-val",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: "grant",
          ingestUrl: "https://ingest.example.com",
          maxDrainStepsPerCall: 0,
        ),
      );
      await expectRejected(
        "live-val",
        const PhoneCoreLiveUploadConfig(
          uploadGrant: "grant",
          ingestUrl: "https://ingest.example.com",
          maxDrainIterations: 0,
        ),
      );
      expect(recordedCalls, isEmpty);
    });
  });

  group("FixedCameraHlsScreen K3 opt-in upload", () {
    testWidgets(
      "keeps legacy upload default and runs opt-in PhoneCore K3 upload when configured",
      (tester) async {
        final chunk1 = writeSegmentFile("ui-1.ts", [1, 2, 3, 4]);
        final chunk2 = writeSegmentFile("ui-2.ts", [5, 6, 7, 8]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recorderChannel, (call) async {
          switch (call.method) {
            case "getCapabilities":
              return {
                "platform": "android",
                "channelAvailable": true,
                "nativeRecorderImplemented": true,
                "cameraRecorderImplemented": false,
                "recorderMode": "synthetic_local",
                "supportedRecorderModes": ["synthetic_local"],
                "cameraIds": <String>[],
                "requiresCameraHardware": false,
                "supportsHlsUpload": true,
                "supportedMimeTypes": ["application/vnd.apple.mpegurl"],
              };
            case "startRecording":
              return {
                "recordingId": "rec-ui-1",
                "recordingDirectoryPath": tempDir.path,
                "startedAt": "2026-11-22T01:00:00.000Z",
                "state": "recording",
              };
            case "stopRecording":
              return {
                "recordingId": "rec-ui-1",
                "recordingDirectoryPath": tempDir.path,
                "chunkPaths": [chunk1.path, chunk2.path],
                "durationSeconds": 4.0,
                "targetDurationSeconds": 2,
                "startedAt": "2026-11-22T01:00:00.000Z",
                "finalizedAt": "2026-11-22T01:00:04.000Z",
                "state": "finalized",
              };
            default:
              return null;
          }
        });

        mockUploadChannel((call) async {
          switch (call.method) {
            case "startSession":
            case "enqueueSegment":
            case "markRecordingStopped":
              return snapshotMap(
                sessionId: "session-k3-ui",
                slot: "B",
                totalSegments: 2,
                activeSegments: 2,
              );
            case "drainOnce":
              return {
                "stepsTaken": 2,
                "didWork": true,
                "hasPendingWork": false,
                "nextWakeAtMs": null,
              };
            case "getSnapshot":
              return snapshotMap(
                sessionId: "session-k3-ui",
                slot: "B",
                manifestState: "complete",
                totalSegments: 2,
                activeSegments: 0,
                verifiedSegments: 2,
                failedSegments: 0,
                isComplete: true,
              );
            default:
              return null;
          }
        });

        await tester.pumpWidget(
          const MaterialApp(home: FixedCameraHlsScreen()),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          "session-k3-ui",
        );

        await tester.tap(find.byKey(const Key("startRecordingButton")));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key("stopRecordingButton")));
        await tester.pumpAndSettle();

        // Legacy upload remains the default before toggling K3 mode on.
        expect(find.text("Upload to media-timeline"), findsOneWidget);
        expect(find.byKey(const Key("k3IngestUrlField")), findsNothing);
        final uploadBtnFinder = find.byKey(const Key("uploadButton"));
        await tester.ensureVisible(uploadBtnFinder);
        await tester.tap(uploadBtnFinder);
        await tester.pumpAndSettle();
        // Legacy path does not invoke PhoneCore channel.
        expect(recordedCalls, isEmpty);

        final k3SwitchFinder =
            find.byKey(const Key("usePhoneCoreK3UploadSwitch"));
        await tester.ensureVisible(k3SwitchFinder);
        await tester.tap(k3SwitchFinder);
        await tester.pumpAndSettle();

        expect(find.text("Upload via PhoneCore K3"), findsOneWidget);
        expect(find.byKey(const Key("k3IngestUrlField")), findsOneWidget);
        expect(find.byKey(const Key("k3UploadGrantField")), findsOneWidget);

        // Missing K3 inputs reports validation feedback without invoking channel.
        await tester.ensureVisible(uploadBtnFinder);
        await tester.tap(uploadBtnFinder);
        await tester.pumpAndSettle();
        expect(recordedCalls, isEmpty);
        expect(find.byKey(const Key("uploadSummaryText")), findsOneWidget);

        final ingestField = find.byKey(const Key("k3IngestUrlField"));
        await tester.ensureVisible(ingestField);
        await tester.enterText(ingestField, "https://ingest.example.com");

        final grantField = find.byKey(const Key("k3UploadGrantField"));
        await tester.ensureVisible(grantField);
        await tester.enterText(grantField, "header.payload.sig");

        final slotFieldFinder = find.byKey(const Key("k3SlotField"));
        if (slotFieldFinder.evaluate().isNotEmpty) {
          await tester.ensureVisible(slotFieldFinder);
          await tester.enterText(slotFieldFinder, "B");
        }

        await tester.ensureVisible(uploadBtnFinder);
        await tester.tap(uploadBtnFinder);
        await tester.pump();
        for (var i = 0; i < 50 && recordedCalls.length < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(
          recordedCalls.map((c) => c.method).toList(),
          [
            "startSession",
            "enqueueSegment",
            "enqueueSegment",
            "markRecordingStopped",
            "drainOnce",
            "getSnapshot",
          ],
        );
        final startArgs = Map<String, Object?>.from(
          recordedCalls.first.arguments as Map,
        );
        expect(startArgs["sessionId"], "session-k3-ui");
        expect(startArgs["slot"], "B");
        expect(startArgs["ingestUrl"], "https://ingest.example.com");
        expect(startArgs["uploadGrant"], "header.payload.sig");
        final uiEnqueueArgs = recordedCalls
            .where((c) => c.method == "enqueueSegment")
            .map((c) => Map<String, Object?>.from(c.arguments as Map))
            .toList();
        expect(uiEnqueueArgs[0]["sha256"], expectedSha256([1, 2, 3, 4]));
        expect(uiEnqueueArgs[1]["sha256"], expectedSha256([5, 6, 7, 8]));
        expect(find.textContaining("2/2"), findsWidgets);
        expect(find.textContaining("complete=true"), findsOneWidget);
        expect(find.textContaining("pending=0"), findsOneWidget);
        expect(find.textContaining("failed=0"), findsOneWidget);
      },
    );

    testWidgets(
      "reports pending and failed counts when K3 upload finishes incomplete",
      (tester) async {
        final chunk1 = writeSegmentFile("fail-1.ts", [11, 22]);
        final chunk2 = writeSegmentFile("fail-2.ts", [33, 44]);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recorderChannel, (call) async {
          switch (call.method) {
            case "getCapabilities":
              return {
                "platform": "android",
                "channelAvailable": true,
                "nativeRecorderImplemented": true,
                "cameraRecorderImplemented": false,
                "recorderMode": "synthetic_local",
                "supportedRecorderModes": ["synthetic_local"],
                "cameraIds": <String>[],
                "requiresCameraHardware": false,
                "supportsHlsUpload": true,
                "supportedMimeTypes": ["application/vnd.apple.mpegurl"],
              };
            case "startRecording":
              return {
                "recordingId": "rec-ui-fail",
                "recordingDirectoryPath": tempDir.path,
                "state": "recording",
              };
            case "stopRecording":
              return {
                "recordingId": "rec-ui-fail",
                "recordingDirectoryPath": tempDir.path,
                "chunkPaths": [chunk1.path, chunk2.path],
                "durationSeconds": 4.0,
                "state": "finalized",
              };
            default:
              return null;
          }
        });

        mockUploadChannel((call) async {
          switch (call.method) {
            case "startSession":
            case "enqueueSegment":
            case "markRecordingStopped":
              return snapshotMap(
                sessionId: "session-k3-fail",
                totalSegments: 2,
                activeSegments: 2,
              );
            case "drainOnce":
              return {
                "stepsTaken": 2,
                "didWork": true,
                "hasPendingWork": false,
                "nextWakeAtMs": null,
              };
            case "getSnapshot":
              return snapshotMap(
                sessionId: "session-k3-fail",
                manifestState: "partial",
                totalSegments: 2,
                activeSegments: 0,
                verifiedSegments: 1,
                failedSegments: 1,
                isComplete: false,
              );
            default:
              return null;
          }
        });

        await tester.pumpWidget(
          const MaterialApp(home: FixedCameraHlsScreen()),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          "session-k3-fail",
        );
        await tester.tap(find.byKey(const Key("startRecordingButton")));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key("stopRecordingButton")));
        await tester.pumpAndSettle();

        final k3SwitchFinder =
            find.byKey(const Key("usePhoneCoreK3UploadSwitch"));
        await tester.ensureVisible(k3SwitchFinder);
        await tester.tap(k3SwitchFinder);
        await tester.pumpAndSettle();

        final ingestField = find.byKey(const Key("k3IngestUrlField"));
        await tester.ensureVisible(ingestField);
        await tester.enterText(ingestField, "https://ingest.example.com");
        final grantField = find.byKey(const Key("k3UploadGrantField"));
        await tester.ensureVisible(grantField);
        await tester.enterText(grantField, "grant.token");

        final uploadBtnFinder = find.byKey(const Key("uploadButton"));
        await tester.ensureVisible(uploadBtnFinder);
        await tester.tap(uploadBtnFinder);
        await tester.pump();
        for (var i = 0; i < 50 && recordedCalls.length < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        final summaryText = tester
            .widget<Text>(find.byKey(const Key("uploadSummaryText")))
            .data;
        expect(summaryText, contains("verified=1/2"));
        expect(summaryText, contains("complete=false"));
        expect(summaryText, contains("pending=0"));
        expect(summaryText, contains("failed=1"));
      },
    );

    testWidgets(
      "resumes pending persisted K3 uploads via recovery coordinator when toggled on",
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recorderChannel, (call) async {
          if (call.method == "getCapabilities") {
            return {
              "platform": "android",
              "channelAvailable": true,
              "nativeRecorderImplemented": true,
              "cameraRecorderImplemented": false,
              "recorderMode": "synthetic_local",
              "supportedRecorderModes": ["synthetic_local"],
              "cameraIds": <String>[],
              "requiresCameraHardware": false,
              "supportsHlsUpload": true,
              "supportedMimeTypes": ["application/vnd.apple.mpegurl"],
            };
          }
          return null;
        });

        mockUploadChannel((call) async {
          switch (call.method) {
            case "hasPendingWork":
              return {
                "hasPendingWork": true,
                "nextWakeAtMs": 0,
                "pendingSessionCount": 1,
                "pendingSegmentCount": 2,
                "pendingBytes": 512,
                "pendingSessionIds": ["persisted-session-1"],
              };
            case "drainOnce":
              return {
                "stepsTaken": 3,
                "didWork": true,
                "hasPendingWork": false,
                "nextWakeAtMs": null,
                "pendingSessionCount": 0,
                "pendingSegmentCount": 0,
                "pendingBytes": 0,
                "pendingSessionIds": <String>[],
              };
            default:
              return null;
          }
        });

        await tester.pumpWidget(
          MaterialApp(
            home: FixedCameraHlsScreen(
              k3Recovery: PhoneCoreLiveUploadRecovery(
                nowMs: () => 1700000000000,
                isPlatformSupported: () => true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key("resumePendingK3UploadsButton")),
          findsNothing,
        );

        final k3SwitchFinder =
            find.byKey(const Key("usePhoneCoreK3UploadSwitch"));
        await tester.ensureVisible(k3SwitchFinder);
        await tester.tap(k3SwitchFinder);
        await tester.pumpAndSettle();
        expect(recordedCalls, isEmpty);

        final resumeButtonFinder =
            find.byKey(const Key("resumePendingK3UploadsButton"));
        expect(resumeButtonFinder, findsOneWidget);
        await tester.ensureVisible(resumeButtonFinder);
        await tester.tap(resumeButtonFinder);
        await tester.pumpAndSettle();

        expect(
          recordedCalls.map((c) => c.method).toList(),
          ["hasPendingWork", "drainOnce"],
        );
        final summaryText = tester
            .widget<Text>(find.byKey(const Key("uploadSummaryText")))
            .data;
        expect(summaryText, contains("drained"));
        expect(summaryText, contains("steps=3"));
      },
    );
  });
}
