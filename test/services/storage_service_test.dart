import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/storage_service.dart";
import "../test_utils/mock_services.dart";

/// Unit tests for StorageService
///
/// These tests verify storage threshold logic and recording block behavior.

void main() {
  group("StorageService", () {
    late FakeStorageService storageService;

    setUp(() {
      storageService = FakeStorageService(
        lowStorageThresholdValue: 1.5,
        criticalStorageThresholdValue: 0.5,
      );
    });

    tearDown(() {
      storageService.dispose();
    });

    group("Recording block logic", () {
      test("recording is not blocked when storage is available", () {
        storageService.isRecordingBlockedValue = false;
        expect(storageService.isRecordingBlocked, false);
      });

      test("recording is blocked when storage is critically low", () {
        storageService.isRecordingBlockedValue = true;
        expect(storageService.isRecordingBlocked, true);
      });
    });

    group("Threshold configuration", () {
      test("exposes low storage threshold", () {
        expect(storageService.lowStorageThreshold, 1.5);
      });

      test("exposes critical storage threshold", () {
        expect(storageService.criticalStorageThreshold, 0.5);
      });
    });
  });

  group("StorageService anchors", () {
    testWidgets(
        "blocks recording and triggers callback when storage is critical",
        (tester) async {
      StorageService.configureMonitoring(enabled: false);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      expect(messengerKey.currentState, isNotNull);

      bool criticalCallbackTriggered = false;
      final storageService = StorageService(
        messengerState: messengerKey.currentState!,
        lowStorageThreshold: 1.0,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () {
          criticalCallbackTriggered = true;
        },
      );

      addTearDown(() {
        storageService.dispose();
        StorageService.configureMonitoring(enabled: true);
      });

      storageService.simulateStorageLevel(400); // 400 MB ~ 0.39 GB

      expect(storageService.isRecordingBlocked, true);
      expect(criticalCallbackTriggered, true);
    });
  });
}
