import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";

import "package:hydracam/models/captured_video.dart";
import "package:hydracam/screens/master_video_recording_screen.dart";

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
}

class _PreviewHost extends StatelessWidget {
  const _PreviewHost({
    required this.cameraService,
    required this.onStopRecording,
  });

  final MockCameraService cameraService;
  final Future<CapturedVideo> Function() onStopRecording;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MasterVideoRecordingScreen(
                  cameraService: cameraService,
                  onStopRecording: onStopRecording,
                ),
              ),
            );
          },
          child: const Text("Open preview"),
        ),
      ),
    );
  }
}
