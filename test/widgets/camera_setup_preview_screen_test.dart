import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/screens/camera_setup_preview_screen.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/device_level_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/widgets/hydracam_surface.dart";

void main() {
  setUpAll(() {
    CameraServiceSingleton.initialize(
      StorageService(
        messengerState: null,
        lowStorageThreshold: 1.5,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () async {},
      ),
      useMockCamera: true,
    );
  });

  testWidgets("renders perspective selector and level overlay", (tester) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraSetupPreviewScreen(
          title: "Prepare Camera",
          preview: const ColoredBox(color: AppTheme.cameraCanvas),
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
    expect(find.byType(HydraCamSurface), findsWidgets);
    expect(find.byType(HydraCamStatusChip), findsOneWidget);
    expect(find.text("Camera ready"), findsOneWidget);
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
          preview: const ColoredBox(color: AppTheme.cameraCanvas),
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

  testWidgets("fits short phone viewports without overflow", (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(360, 320));

    await tester.pumpWidget(
      MaterialApp(
        home: CameraSetupPreviewScreen(
          title: "Prepare Camera",
          preview: const ColoredBox(color: AppTheme.cameraCanvas),
          initialReading: DeviceLevelReading(
            rollDegrees: 1,
            pitchDegrees: 0,
            capturedAt: DateTime.utc(2026, 6, 8),
            sensorAvailable: true,
          ),
          onStartRecording: () {},
        ),
      ),
    );

    expect(find.text("Prepare Camera"), findsOneWidget);
    expect(find.text("Camera perspective"), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(find.text("Start Recording"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("standalone setup route can return to normal app",
      (tester) async {
    var openedNormalApp = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraSetupStandaloneScreen(
          onOpenNormalApp: () {
            openedNormalApp = true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Prepare Camera"), findsOneWidget);
    expect(find.text("Open HydraCam"), findsOneWidget);

    await tester.tap(find.text("Open HydraCam"));

    expect(openedNormalApp, isTrue);
  });
}
