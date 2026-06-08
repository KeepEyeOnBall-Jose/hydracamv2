import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/screens/camera_setup_preview_screen.dart";
import "package:hydracam/services/device_level_service.dart";

void main() {
  testWidgets("renders perspective selector and level overlay", (tester) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraSetupPreviewScreen(
          title: "Prepare Camera",
          preview: const ColoredBox(color: Colors.black),
          initialReading: DeviceLevelReading(
            rollDegrees: 1,
            pitchDegrees: 0,
            capturedAt: DateTime.utc(2026, 6, 8),
            sensorAvailable: true,
          ),
          onStartRecording: () {
            started = true;
          },
        ),
      ),
    );

    expect(find.text("Prepare Camera"), findsOneWidget);
    expect(find.text("Camera perspective"), findsOneWidget);
    expect(find.text("Level"), findsOneWidget);

    await tester.tap(find.text("Start Recording"));
    expect(started, isTrue);
  });

  testWidgets("warn-only flow allows recording while red tilted",
      (tester) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraSetupPreviewScreen(
          title: "Prepare Camera",
          preview: const ColoredBox(color: Colors.black),
          initialReading: DeviceLevelReading(
            rollDegrees: 8,
            pitchDegrees: 0,
            capturedAt: DateTime.utc(2026, 6, 8),
            sensorAvailable: true,
          ),
          initialPerspective:
              CameraPerspectiveMetadata.fromId("tin_back_floor_center"),
          onStartRecording: () {
            started = true;
          },
        ),
      ),
    );

    expect(find.text("Tilted"), findsOneWidget);

    await tester.tap(find.text("Start Recording"));
    expect(started, isTrue);
  });
}
