import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/device_level_service.dart";
import "package:hydracam/widgets/camera_level_overlay.dart";

void main() {
  testWidgets("shows green guidance for level devices", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CameraLevelOverlay(
          reading: DeviceLevelReading(
            rollDegrees: 0.4,
            pitchDegrees: -2.1,
            capturedAt: DateTime.utc(2026, 6, 8),
            sensorAvailable: true,
          ),
          child: const SizedBox(width: 240, height: 180),
        ),
      ),
    );

    expect(find.text("Level"), findsOneWidget);
    expect(find.textContaining("Roll 0.4"), findsOneWidget);
    expect(find.textContaining("Pitch -2.1"), findsOneWidget);
  });

  testWidgets("warn-only overlay still renders action area when tilted",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CameraLevelOverlay(
          reading: DeviceLevelReading(
            rollDegrees: 8,
            pitchDegrees: 1,
            capturedAt: DateTime.utc(2026, 6, 8),
            sensorAvailable: true,
          ),
          child: const SizedBox(width: 240, height: 180),
        ),
      ),
    );

    expect(find.text("Tilted"), findsOneWidget);
    expect(find.textContaining("Roll 8.0"), findsOneWidget);
    expect(find.textContaining("Pitch 1.0"), findsOneWidget);
  });
}
