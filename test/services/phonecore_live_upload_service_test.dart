import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/phonecore_live_upload_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PhoneCoreLiveUploadService.channelName);
  late List<MethodCall> calls;

  void mockChannel(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  Map<String, Object?> sampleSnapshotMap({
    String sessionId = "live-session-1",
    String slot = "A",
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
    List<Map<String, Object?>> items = const [],
  }) {
    return {
      "sessionId": sessionId,
      "slot": slot,
      "grantedTiers": ["proxy"],
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
      "items": items,
    };
  }

  setUp(() {
    calls = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test("startSession invokes channel and parses immutable snapshot", () async {
    mockChannel((call) async {
      expect(call.method, "startSession");
      expect(call.arguments, {
        "sessionId": "live-session-1",
        "slot": "A",
        "uploadGrant": "header.payload.sig",
        "ingestUrl": "https://ingest.example.com",
        "nowMs": 1700000000000,
      });
      return sampleSnapshotMap();
    });

    final service = PhoneCoreLiveUploadService();
    final snapshot = await service.startSession(
      sessionId: "live-session-1",
      slot: "A",
      uploadGrant: "header.payload.sig",
      ingestUrl: "https://ingest.example.com",
      nowMs: 1700000000000,
    );

    expect(calls, hasLength(1));
    expect(snapshot.sessionId, "live-session-1");
    expect(snapshot.slot, "A");
    expect(snapshot.grantedTiers, ["proxy"]);
    expect(snapshot.stoppedAtMs, 0);
    expect(snapshot.lastSeqProxy, -1);
    expect(snapshot.lastSeqMaster, -1);
    expect(snapshot.manifestState, isNull);
    expect(snapshot.totalSegments, 0);
    expect(snapshot.isComplete, isFalse);
    expect(snapshot.items, isEmpty);
    expect(
      () => snapshot.grantedTiers.add("master"),
      throwsUnsupportedError,
    );
  });

  test("enqueueSegment forwards segment metadata and parses item list",
      () async {
    mockChannel((call) async {
      expect(call.method, "enqueueSegment");
      expect(call.arguments, {
        "sessionId": "live-session-1",
        "slot": "A",
        "tier": "proxy",
        "seq": 0,
        "filePath": "/data/local/tmp/proxy-0.ts",
        "sha256": "deadbeef",
        "mediaStartServerMs": 1700000001000,
        "durationMs": 6000,
      });
      return sampleSnapshotMap(
        lastSeqProxy: 0,
        totalSegments: 1,
        activeSegments: 1,
        pendingBytes: 2048,
        items: [
          {
            "key": "live-session-1/proxy/0",
            "sessionId": "live-session-1",
            "slot": "A",
            "tier": "proxy",
            "seq": 0,
            "filePath": "/data/local/tmp/proxy-0.ts",
            "bytes": 2048,
            "sha256": "deadbeef",
            "mediaStartServerMs": 1700000001000,
            "durationMs": 6000,
            "state": "PENDING",
            "uploadId": null,
            "verifyRestarts": 0,
            "attempts": 0,
            "nextAttemptAtMs": 0,
            "lastError": null,
            "createdAtMs": 1700000001500,
            "updatedAtMs": 1700000001500,
          },
        ],
      );
    });

    final service = PhoneCoreLiveUploadService();
    final snapshot = await service.enqueueSegment(
      sessionId: "live-session-1",
      slot: "A",
      tier: "proxy",
      seq: 0,
      filePath: "/data/local/tmp/proxy-0.ts",
      sha256: "deadbeef",
      mediaStartServerMs: 1700000001000,
      durationMs: 6000,
    );

    expect(snapshot.totalSegments, 1);
    expect(snapshot.activeSegments, 1);
    expect(snapshot.pendingBytes, 2048);
    expect(snapshot.items, hasLength(1));
    final item = snapshot.items.first;
    expect(item.key, "live-session-1/proxy/0");
    expect(item.tier, "proxy");
    expect(item.seq, 0);
    expect(item.bytes, 2048);
    expect(item.state, "PENDING");
    expect(item.uploadId, isNull);
    expect(
      () => snapshot.items.add(item),
      throwsUnsupportedError,
    );
  });

  test("markRecordingStopped handles snapshot and null for unknown session",
      () async {
    mockChannel((call) async {
      expect(call.method, "markRecordingStopped");
      final args = call.arguments as Map;
      if (args["sessionId"] == "unknown") {
        expect(args.containsKey("stoppedAtMs"), isFalse);
        return null;
      }
      expect(args, {
        "sessionId": "live-session-1",
        "stoppedAtMs": 1700000008000,
      });
      return sampleSnapshotMap(
        stoppedAtMs: 1700000008000,
        lastSeqProxy: 2,
      );
    });

    final service = PhoneCoreLiveUploadService();
    final unknown = await service.markRecordingStopped(sessionId: "unknown");
    expect(unknown, isNull);

    final stopped = await service.markRecordingStopped(
      sessionId: "live-session-1",
      stoppedAtMs: 1700000008000,
    );
    expect(stopped, isNotNull);
    expect(stopped!.stoppedAtMs, 1700000008000);
    expect(stopped.lastSeqProxy, 2);
  });

  test(
      "drainOnce forwards optional maxSteps, validates range, and parses result",
      () async {
    mockChannel((call) async {
      expect(call.method, "drainOnce");
      final args = call.arguments as Map?;
      if (args == null) {
        return {
          "stepsTaken": 0,
          "didWork": false,
          "hasPendingWork": false,
          "nextWakeAtMs": null,
        };
      }
      expect(args, {"maxSteps": 12});
      return {
        "stepsTaken": 3,
        "didWork": true,
        "hasPendingWork": true,
        "nextWakeAtMs": 1700000010000,
      };
    });

    final service = PhoneCoreLiveUploadService();
    final idle = await service.drainOnce();
    expect(idle.stepsTaken, 0);
    expect(idle.didWork, isFalse);
    expect(idle.hasPendingWork, isFalse);
    expect(idle.nextWakeAtMs, isNull);

    final worked = await service.drainOnce(maxSteps: 12);
    expect(worked.stepsTaken, 3);
    expect(worked.didWork, isTrue);
    expect(worked.hasPendingWork, isTrue);
    expect(worked.nextWakeAtMs, 1700000010000);

    expect(() => service.drainOnce(maxSteps: 0), throwsArgumentError);
    expect(() => service.drainOnce(maxSteps: 51), throwsArgumentError);
  });

  test("getSnapshot returns null when unknown and snapshot when known",
      () async {
    mockChannel((call) async {
      expect(call.method, "getSnapshot");
      final args = call.arguments as Map;
      if (args["sessionId"] == "missing") {
        return null;
      }
      expect(args, {"sessionId": "live-session-1"});
      return sampleSnapshotMap(
        stoppedAtMs: 1700000008000,
        lastSeqProxy: 0,
        manifestState: "complete",
        totalSegments: 1,
        verifiedSegments: 1,
        isComplete: true,
      );
    });

    final service = PhoneCoreLiveUploadService();
    expect(await service.getSnapshot("missing"), isNull);

    final snapshot = await service.getSnapshot("live-session-1");
    expect(snapshot, isNotNull);
    expect(snapshot!.manifestState, "complete");
    expect(snapshot.isComplete, isTrue);
    expect(snapshot.verifiedSegments, 1);
  });

  test("hasPendingWork queries channel and parses wake timestamp and summary",
      () async {
    mockChannel((call) async {
      expect(call.method, "hasPendingWork");
      expect(call.arguments, isNull);
      return {
        "hasPendingWork": true,
        "nextWakeAtMs": 1700000005000,
        "pendingSessionCount": 2,
        "pendingSegmentCount": 5,
        "pendingBytes": 4096,
        "pendingSessionIds": ["s1", "s2"],
      };
    });

    final service = PhoneCoreLiveUploadService();
    final pending = await service.hasPendingWork();
    expect(pending.hasPendingWork, isTrue);
    expect(pending.nextWakeAtMs, 1700000005000);
    expect(pending.pendingSessionCount, 2);
    expect(pending.pendingSegmentCount, 5);
    expect(pending.pendingBytes, 4096);
    expect(pending.pendingSessionIds, ["s1", "s2"]);
    expect(
      () => pending.pendingSessionIds.add("s3"),
      throwsUnsupportedError,
    );
  });

  test(
      "hasPendingWork and drainOnce default optional summary fields when absent",
      () async {
    mockChannel((call) async {
      if (call.method == "hasPendingWork") {
        return {
          "hasPendingWork": true,
          "nextWakeAtMs": 1700000005000,
        };
      }
      return {
        "stepsTaken": 2,
        "didWork": true,
        "hasPendingWork": true,
        "nextWakeAtMs": 1700000007000,
        "pendingSessionCount": 1,
        "pendingSegmentCount": 3,
        "pendingBytes": 1024,
        "pendingSessionIds": ["s1"],
      };
    });

    final service = PhoneCoreLiveUploadService();
    final pending = await service.hasPendingWork();
    expect(pending.hasPendingWork, isTrue);
    expect(pending.pendingSessionCount, 0);
    expect(pending.pendingSegmentCount, 0);
    expect(pending.pendingBytes, 0);
    expect(pending.pendingSessionIds, isEmpty);

    final drain = await service.drainOnce();
    expect(drain.pendingSessionCount, 1);
    expect(drain.pendingSegmentCount, 3);
    expect(drain.pendingBytes, 1024);
    expect(drain.pendingSessionIds, ["s1"]);
    expect(
      () => drain.pendingSessionIds.add("s2"),
      throwsUnsupportedError,
    );
  });

  test("fromMap throws FormatException on null or malformed native payloads",
      () async {
    mockChannel((call) async => null);
    final service = PhoneCoreLiveUploadService();

    expect(
      () => service.startSession(
        sessionId: "s1",
        slot: "A",
        uploadGrant: "g",
        ingestUrl: "https://ingest.example.com",
      ),
      throwsFormatException,
    );
    expect(
      () => service.drainOnce(),
      throwsFormatException,
    );
    expect(
      () => service.hasPendingWork(),
      throwsFormatException,
    );
    expect(
      () => PhoneCoreLiveUploadSnapshot.fromMap({"sessionId": "s1"}),
      throwsFormatException,
    );
    expect(
      () => PhoneCoreDrainResult.fromMap({"stepsTaken": "nope"}),
      throwsFormatException,
    );
    expect(
      () => PhoneCorePendingWork.fromMap({
        "hasPendingWork": true,
        "nextWakeAtMs": null,
        "pendingSessionIds": "bad",
      }),
      throwsFormatException,
    );
    expect(
      () => PhoneCorePendingWork.fromMap({
        "hasPendingWork": true,
        "nextWakeAtMs": null,
        "pendingSessionIds": [123],
      }),
      throwsFormatException,
    );
  });
}
