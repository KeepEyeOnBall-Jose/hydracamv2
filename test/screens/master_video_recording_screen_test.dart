import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";

import "package:hydracam/models/captured_video.dart";
import "package:hydracam/screens/master_video_recording_screen.dart";
import "package:hydracam/services/settings_service.dart";

import "../test_utils/mock_services.dart";

void main() {
  testWidgets(
      "recording preview exits when no recording is active and no controller exists",
      (WidgetTester tester) async {
    final cameraService = MockCameraService();
    final recordingInterrupted = ValueNotifier<bool>(false);
    var stopRecordingCalled = false;

    when(() => cameraService.recordingInterrupted)
        .thenReturn(recordingInterrupted);
    when(() => cameraService.isRecording).thenReturn(false);
    when(() => cameraService.controller).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: _PreviewHost(
          cameraService: cameraService,
          onStopRecording: () async {
            stopRecordingCalled = true;
            throw StateError("stop recording should not be called");
          },
        ),
      ),
    );

    await tester.tap(find.text("Open preview"));
    await tester.pumpAndSettle();

    expect(find.byType(MasterVideoRecordingScreen), findsOneWidget);

    await tester.tap(find.byTooltip("Exit recording preview"));
    await tester.pumpAndSettle();

    expect(find.byType(MasterVideoRecordingScreen), findsNothing);
    expect(find.text("Open preview"), findsOneWidget);
    expect(stopRecordingCalled, isFalse);

    recordingInterrupted.dispose();
  });

  testWidgets("recording interruption listener is removed on dispose",
      (WidgetTester tester) async {
    final cameraService = MockCameraService();
    final recordingInterrupted = ValueNotifier<bool>(false);

    when(() => cameraService.recordingInterrupted)
        .thenReturn(recordingInterrupted);
    when(() => cameraService.isRecording).thenReturn(false);
    when(() => cameraService.controller).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: _PreviewHost(
          cameraService: cameraService,
          onStopRecording: () async {
            throw StateError("stop recording should not be called");
          },
        ),
      ),
    );

    await tester.tap(find.text("Open preview"));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip("Exit recording preview"));
    await tester.pumpAndSettle();

    recordingInterrupted.value = true;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MasterVideoRecordingScreen), findsNothing);
    expect(find.text("Open preview"), findsOneWidget);

    recordingInterrupted.dispose();
  });

  testWidgets("stop recording button returns captured video",
      (WidgetTester tester) async {
    SettingsService.overrideTimerDuration(0);
    addTearDown(SettingsService.clearTestOverrides);

    final cameraService = MockCameraService();
    final recordingInterrupted = ValueNotifier<bool>(false);
    final tempDir =
        Directory.systemTemp.createTempSync("master_recording_screen_test");
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final videoFile = File("${tempDir.path}/master-recorded.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedVideo = CapturedVideo(
      videoPath: videoFile.path,
      slaveDeviceId: "master-device",
      startRecordingDate: DateTime.utc(2026, 6, 9, 3),
      endRecordingDate: DateTime.utc(2026, 6, 9, 3, 1),
      receivedDate: DateTime.utc(2026, 6, 9, 3, 2),
    );
    var stopCallCount = 0;
    CapturedVideo? returnedVideo;

    when(() => cameraService.recordingInterrupted)
        .thenReturn(recordingInterrupted);
    when(() => cameraService.isRecording).thenReturn(true);
    when(() => cameraService.controller).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: _PreviewHost(
          cameraService: cameraService,
          onStopRecording: () async {
            stopCallCount += 1;
            return capturedVideo;
          },
          onPopped: (video) {
            returnedVideo = video;
          },
        ),
      ),
    );

    await tester.tap(find.text("Open preview"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Stop Recording"));
    await tester.pumpAndSettle();

    expect(find.byType(MasterVideoRecordingScreen), findsNothing);
    expect(stopCallCount, 1);
    expect(returnedVideo, same(capturedVideo));

    recordingInterrupted.dispose();
  });

  testWidgets("stop recording ignores settings completion after dispose",
      (WidgetTester tester) async {
    final timerDuration = Completer<int>();
    SettingsService.overrideTimerDurationFutureForTests(
      () => timerDuration.future,
    );
    addTearDown(SettingsService.clearTestOverrides);

    final cameraService = MockCameraService();
    final recordingInterrupted = ValueNotifier<bool>(false);
    var stopRecordingCalled = false;

    when(() => cameraService.recordingInterrupted)
        .thenReturn(recordingInterrupted);
    when(() => cameraService.isRecording).thenReturn(true);
    when(() => cameraService.controller).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: _PreviewHost(
          cameraService: cameraService,
          onStopRecording: () async {
            stopRecordingCalled = true;
            throw StateError("disposed preview should not stop recording");
          },
        ),
      ),
    );

    await tester.tap(find.text("Open preview"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Stop Recording"));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    timerDuration.complete(0);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(stopRecordingCalled, isFalse);

    recordingInterrupted.dispose();
  });
}

class _PreviewHost extends StatelessWidget {
  const _PreviewHost({
    required this.cameraService,
    required this.onStopRecording,
    this.onPopped,
  });

  final MockCameraService cameraService;
  final Future<CapturedVideo> Function() onStopRecording;
  final void Function(CapturedVideo?)? onPopped;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final capturedVideo =
                await Navigator.of(context).push<CapturedVideo>(
              MaterialPageRoute(
                builder: (_) => MasterVideoRecordingScreen(
                  cameraService: cameraService,
                  onStopRecording: onStopRecording,
                ),
              ),
            );
            onPopped?.call(capturedVideo);
          },
          child: const Text("Open preview"),
        ),
      ),
    );
  }
}
