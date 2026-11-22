import "dart:async";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/phonecore_live_upload_recovery.dart";
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

  setUp(() {
    calls = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group("PhoneCoreLiveUploadRecovery", () {
    test("no-ops immediately without drainOnce when queue has no pending work",
        () async {
      mockChannel((call) async {
        expect(call.method, "hasPendingWork");
        return {
          "hasPendingWork": false,
          "nextWakeAtMs": null,
          "pendingSessionCount": 0,
          "pendingSegmentCount": 0,
          "pendingBytes": 0,
          "pendingSessionIds": <String>[],
        };
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        sleep: (duration) async => sleeps.add(duration),
        nowMs: () => 1700000000000,
        isPlatformSupported: () => true,
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.idle);
      expect(result.didWork, isFalse);
      expect(result.hasPendingWork, isFalse);
      expect(result.drainIterations, 0);
      expect(result.totalStepsTaken, 0);
      expect(result.pendingSessionCount, 0);
      expect(result.pendingSegmentCount, 0);
      expect(result.pendingBytes, 0);
      expect(result.pendingSessionIds, isEmpty);
      expect(calls.map((c) => c.method).toList(), ["hasPendingWork"]);
      expect(sleeps, isEmpty);
      expect(recovery.lastResult, same(result));
      expect(recovery.isRecovering, isFalse);
    });

    test(
        "returns unavailable without touching channel on unsupported platforms",
        () async {
      mockChannel((call) async {
        fail("Channel should not be invoked when platform is unsupported.");
      });

      final recovery = PhoneCoreLiveUploadRecovery(
        isPlatformSupported: () => false,
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.unavailable);
      expect(result.didWork, isFalse);
      expect(result.hasPendingWork, isFalse);
      expect(calls, isEmpty);
    });

    test(
        "handles MissingPluginException gracefully on startup without throwing",
        () async {
      // No mock handler registered -> throws MissingPluginException.
      final recovery = PhoneCoreLiveUploadRecovery(
        isPlatformSupported: () => true,
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.unavailable);
      expect(result.didWork, isFalse);
      expect(result.hasPendingWork, isFalse);
      expect(result.drainIterations, 0);
      expect(result.errorMessage, isNotEmpty);
      expect(recovery.isRecovering, isFalse);
    });

    test("handles PlatformException gracefully without throwing", () async {
      mockChannel((call) async {
        if (call.method == "hasPendingWork") {
          throw PlatformException(
            code: "phonecore_live_upload_shutdown",
            message: "Executor already shut down",
          );
        }
        return null;
      });

      final logs = <String>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        isPlatformSupported: () => true,
        log: logs.add,
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.failed);
      expect(result.didWork, isFalse);
      expect(result.errorMessage, contains("Executor already shut down"));
      expect(logs, isNotEmpty);
      expect(recovery.isRecovering, isFalse);
    });

    test(
        "drains pending queue to completion across multiple steps and bounded poll waits",
        () async {
      var now = 1700000000000;
      var drainCount = 0;
      mockChannel((call) async {
        switch (call.method) {
          case "hasPendingWork":
            return {
              "hasPendingWork": true,
              "nextWakeAtMs": 0,
              "pendingSessionCount": 2,
              "pendingSegmentCount": 5,
              "pendingBytes": 4096,
              "pendingSessionIds": ["sess-a", "sess-b"],
            };
          case "drainOnce":
            drainCount += 1;
            expect(call.arguments, {"maxSteps": 4});
            if (drainCount == 1) {
              return {
                "stepsTaken": 4,
                "didWork": true,
                "hasPendingWork": true,
                "nextWakeAtMs": 0,
                "pendingSessionCount": 1,
                "pendingSegmentCount": 2,
                "pendingBytes": 1024,
                "pendingSessionIds": ["sess-b"],
              };
            }
            if (drainCount == 2) {
              return {
                "stepsTaken": 1,
                "didWork": true,
                "hasPendingWork": true,
                "nextWakeAtMs": now + 2000,
                "pendingSessionCount": 1,
                "pendingSegmentCount": 1,
                "pendingBytes": 512,
                "pendingSessionIds": ["sess-b"],
              };
            }
            return {
              "stepsTaken": 2,
              "didWork": true,
              "hasPendingWork": false,
              "nextWakeAtMs": null,
              "pendingSessionCount": 0,
              "pendingSegmentCount": 0,
              "pendingBytes": 0,
              "pendingSessionIds": <String>[],
            };
          default:
            fail("Unexpected method: ${call.method}");
        }
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => now,
        sleep: (duration) async {
          sleeps.add(duration);
          now += duration.inMilliseconds;
        },
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxStepsPerDrain: 4,
          maxDrainIterations: 6,
          maxTotalRecoveryDuration: Duration(seconds: 20),
          maxWakeWaitPerStep: Duration(seconds: 5),
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.drained);
      expect(result.didWork, isTrue);
      expect(result.hasPendingWork, isFalse);
      expect(result.nextWakeAtMs, isNull);
      expect(result.drainIterations, 3);
      expect(result.totalStepsTaken, 7);
      expect(result.pendingSessionCount, 0);
      expect(result.pendingSegmentCount, 0);
      expect(result.pendingBytes, 0);
      expect(result.pendingSessionIds, isEmpty);
      expect(sleeps, [const Duration(milliseconds: 2000)]);
      expect(
        calls.map((c) => c.method).toList(),
        ["hasPendingWork", "drainOnce", "drainOnce", "drainOnce"],
      );
    });

    test(
        "waits bounded initial nextWakeAtMs before draining when within budget",
        () async {
      var now = 1700000000000;
      mockChannel((call) async {
        switch (call.method) {
          case "hasPendingWork":
            return {
              "hasPendingWork": true,
              "nextWakeAtMs": now + 1500,
              "pendingSessionCount": 1,
              "pendingSegmentCount": 1,
              "pendingBytes": 256,
              "pendingSessionIds": ["sess-poll"],
            };
          case "drainOnce":
            expect(now, 1700000001500);
            return {
              "stepsTaken": 2,
              "didWork": true,
              "hasPendingWork": false,
              "nextWakeAtMs": null,
              "pendingSessionCount": 0,
              "pendingSegmentCount": 0,
              "pendingBytes": 0,
              "pendingSessionIds": <String>[],
            };
          default:
            fail("Unexpected method: ${call.method}");
        }
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => now,
        sleep: (duration) async {
          sleeps.add(duration);
          now += duration.inMilliseconds;
        },
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxWakeWaitPerStep: Duration(seconds: 3),
          maxTotalRecoveryDuration: Duration(seconds: 10),
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.drained);
      expect(sleeps, [const Duration(milliseconds: 1500)]);
      expect(result.drainIterations, 1);
      expect(result.totalStepsTaken, 2);
    });

    test(
        "stops cleanly without sleeping when initial backoff exceeds maxWakeWaitPerStep",
        () async {
      const now = 1700000000000;
      mockChannel((call) async {
        expect(call.method, "hasPendingWork");
        return {
          "hasPendingWork": true,
          "nextWakeAtMs": now + 30000,
          "pendingSessionCount": 1,
          "pendingSegmentCount": 3,
          "pendingBytes": 1500,
          "pendingSessionIds": ["sess-backoff"],
        };
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => now,
        sleep: (duration) async => sleeps.add(duration),
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxWakeWaitPerStep: Duration(seconds: 5),
          maxTotalRecoveryDuration: Duration(seconds: 60),
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.deferred);
      expect(result.didWork, isFalse);
      expect(result.hasPendingWork, isTrue);
      expect(result.nextWakeAtMs, now + 30000);
      expect(result.pendingSessionCount, 1);
      expect(result.pendingSegmentCount, 3);
      expect(result.pendingBytes, 1500);
      expect(result.pendingSessionIds, ["sess-backoff"]);
      expect(result.drainIterations, 0);
      expect(sleeps, isEmpty);
      expect(calls.map((c) => c.method).toList(), ["hasPendingWork"]);
    });

    test("stops cleanly when post-drain cumulative recovery budget is exceeded",
        () async {
      var now = 1700000000000;
      var drainCount = 0;
      mockChannel((call) async {
        switch (call.method) {
          case "hasPendingWork":
            return {
              "hasPendingWork": true,
              "nextWakeAtMs": 0,
              "pendingSessionCount": 1,
              "pendingSegmentCount": 2,
              "pendingBytes": 800,
              "pendingSessionIds": ["sess-budget"],
            };
          case "drainOnce":
            drainCount += 1;
            return {
              "stepsTaken": 1,
              "didWork": true,
              "hasPendingWork": true,
              "nextWakeAtMs": now + 2500,
              "pendingSessionCount": 1,
              "pendingSegmentCount": 1,
              "pendingBytes": 400,
              "pendingSessionIds": ["sess-budget"],
            };
          default:
            fail("Unexpected method: ${call.method}");
        }
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => now,
        sleep: (duration) async {
          sleeps.add(duration);
          now += duration.inMilliseconds;
        },
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxDrainIterations: 5,
          maxWakeWaitPerStep: Duration(seconds: 3),
          maxTotalRecoveryDuration: Duration(seconds: 4),
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.deferred);
      expect(drainCount, 2);
      expect(result.drainIterations, 2);
      expect(result.totalStepsTaken, 2);
      expect(result.hasPendingWork, isTrue);
      expect(result.nextWakeAtMs, 1700000005000);
      expect(result.pendingSessionCount, 1);
      expect(result.pendingSegmentCount, 1);
      expect(result.pendingBytes, 400);
      expect(sleeps, [const Duration(milliseconds: 2500)]);
    });

    test("stops cleanly at maxDrainIterations when queue remains active",
        () async {
      mockChannel((call) async {
        switch (call.method) {
          case "hasPendingWork":
            return {
              "hasPendingWork": true,
              "nextWakeAtMs": 0,
              "pendingSessionCount": 1,
              "pendingSegmentCount": 10,
              "pendingBytes": 5000,
              "pendingSessionIds": ["sess-many"],
            };
          case "drainOnce":
            return {
              "stepsTaken": 2,
              "didWork": true,
              "hasPendingWork": true,
              "nextWakeAtMs": 0,
              "pendingSessionCount": 1,
              "pendingSegmentCount": 6,
              "pendingBytes": 3000,
              "pendingSessionIds": ["sess-many"],
            };
          default:
            return null;
        }
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => 1700000000000,
        sleep: (duration) async => sleeps.add(duration),
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxStepsPerDrain: 2,
          maxDrainIterations: 3,
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.deferred);
      expect(result.drainIterations, 3);
      expect(result.totalStepsTaken, 6);
      expect(result.hasPendingWork, isTrue);
      expect(result.pendingSegmentCount, 6);
      expect(sleeps, isEmpty);
    });

    test("guards against tight spin when drainOnce repeatedly does no work",
        () async {
      mockChannel((call) async {
        switch (call.method) {
          case "hasPendingWork":
            return {"hasPendingWork": true, "nextWakeAtMs": 0};
          case "drainOnce":
            return {
              "stepsTaken": 0,
              "didWork": false,
              "hasPendingWork": true,
              "nextWakeAtMs": 0,
            };
          default:
            return null;
        }
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => 1700000000000,
        sleep: (duration) async => sleeps.add(duration),
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxDrainIterations: 6,
          fallbackIdleDelay: Duration(milliseconds: 100),
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.deferred);
      expect(result.drainIterations, 2);
      expect(result.totalStepsTaken, 0);
      expect(sleeps, [const Duration(milliseconds: 100)]);
    });

    test(
        "deduplicates concurrent calls via single-flight protection and allows sequential re-run",
        () async {
      final hasPendingCompleter = Completer<Map<String, Object?>>();
      var hasPendingCalls = 0;
      var drainCalls = 0;

      mockChannel((call) async {
        if (call.method == "hasPendingWork") {
          hasPendingCalls += 1;
          if (hasPendingCalls == 1) {
            return hasPendingCompleter.future;
          }
          return {"hasPendingWork": false, "nextWakeAtMs": null};
        }
        if (call.method == "drainOnce") {
          drainCalls += 1;
          return {
            "stepsTaken": 1,
            "didWork": true,
            "hasPendingWork": false,
            "nextWakeAtMs": null,
          };
        }
        return null;
      });

      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => 1700000000000,
        isPlatformSupported: () => true,
      );

      final firstFuture = recovery.recoverPendingUploads();
      final secondFuture = recovery.recoverPendingUploads();
      expect(recovery.isRecovering, isTrue);
      expect(hasPendingCalls, 1);

      hasPendingCompleter.complete({
        "hasPendingWork": true,
        "nextWakeAtMs": 0,
        "pendingSessionCount": 1,
        "pendingSegmentCount": 1,
        "pendingBytes": 128,
        "pendingSessionIds": ["sess-concurrent"],
      });

      final results = await Future.wait([firstFuture, secondFuture]);
      expect(identical(results[0], results[1]), isTrue);
      expect(results[0].status, PhoneCoreLiveUploadRecoveryStatus.drained);
      expect(hasPendingCalls, 1);
      expect(drainCalls, 1);
      expect(recovery.isRecovering, isFalse);

      // Once completed, a subsequent resume trigger runs a fresh check.
      final thirdResult = await recovery.recoverPendingUploads();
      expect(thirdResult.status, PhoneCoreLiveUploadRecoveryStatus.idle);
      expect(hasPendingCalls, 2);
    });

    test("handles MissingPluginException mid-drain and malformed payloads",
        () async {
      var mode = "missing_drain";
      mockChannel((call) async {
        if (mode == "missing_drain") {
          if (call.method == "hasPendingWork") {
            return {"hasPendingWork": true, "nextWakeAtMs": 0};
          }
          throw MissingPluginException("Channel detached mid-drain");
        }
        return {"hasPendingWork": "not-a-bool"};
      });

      final logs = <String>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => 1700000000000,
        isPlatformSupported: () => true,
        log: logs.add,
      );

      final missingDrain = await recovery.recoverPendingUploads();
      expect(
          missingDrain.status, PhoneCoreLiveUploadRecoveryStatus.unavailable);
      expect(missingDrain.errorMessage, contains("drainOnce"));

      mode = "malformed";
      final malformed = await recovery.recoverPendingUploads();
      expect(malformed.status, PhoneCoreLiveUploadRecoveryStatus.failed);
      expect(malformed.errorMessage, isNotEmpty);
      expect(logs, isNotEmpty);
    });

    test(
        "stops cleanly after drainOnce when post-drain backoff exceeds maxWakeWaitPerStep",
        () async {
      const now = 1700000000000;
      mockChannel((call) async {
        if (call.method == "hasPendingWork") {
          return {"hasPendingWork": true, "nextWakeAtMs": 0};
        }
        return {
          "stepsTaken": 2,
          "didWork": true,
          "hasPendingWork": true,
          "nextWakeAtMs": now + 60000,
          "pendingSessionCount": 1,
          "pendingSegmentCount": 2,
          "pendingBytes": 1024,
          "pendingSessionIds": ["sess-post-backoff"],
        };
      });

      final sleeps = <Duration>[];
      final recovery = PhoneCoreLiveUploadRecovery(
        nowMs: () => now,
        sleep: (duration) async => sleeps.add(duration),
        isPlatformSupported: () => true,
        config: const PhoneCoreLiveUploadRecoveryConfig(
          maxDrainIterations: 4,
          maxWakeWaitPerStep: Duration(seconds: 5),
          maxTotalRecoveryDuration: Duration(seconds: 60),
        ),
      );

      final result = await recovery.recoverPendingUploads();

      expect(result.status, PhoneCoreLiveUploadRecoveryStatus.deferred);
      expect(result.drainIterations, 1);
      expect(result.totalStepsTaken, 2);
      expect(result.nextWakeAtMs, now + 60000);
      expect(result.pendingSessionIds, ["sess-post-backoff"]);
      expect(sleeps, isEmpty);
    });

    test("validates recovery config bounds eagerly", () {
      expect(
        () => PhoneCoreLiveUploadRecovery(
          config: const PhoneCoreLiveUploadRecoveryConfig(maxStepsPerDrain: 0),
        ),
        throwsRangeError,
      );
      expect(
        () => PhoneCoreLiveUploadRecovery(
          config: const PhoneCoreLiveUploadRecoveryConfig(maxStepsPerDrain: 51),
        ),
        throwsRangeError,
      );
      expect(
        () => PhoneCoreLiveUploadRecovery(
          config:
              const PhoneCoreLiveUploadRecoveryConfig(maxDrainIterations: 0),
        ),
        throwsRangeError,
      );
      expect(
        () => PhoneCoreLiveUploadRecovery(
          config: const PhoneCoreLiveUploadRecoveryConfig(
            maxTotalRecoveryDuration: Duration(milliseconds: -1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => PhoneCoreLiveUploadRecovery(
          config: const PhoneCoreLiveUploadRecoveryConfig(
            maxWakeWaitPerStep: Duration(milliseconds: -1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => PhoneCoreLiveUploadRecovery(
          config: const PhoneCoreLiveUploadRecoveryConfig(
            fallbackIdleDelay: Duration(milliseconds: -1),
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
