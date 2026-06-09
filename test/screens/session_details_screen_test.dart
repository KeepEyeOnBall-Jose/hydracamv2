import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/screens/session_details_screen.dart";
import "package:hydracam/services/session_manager.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testPathProvider = _TestPathProviderPlatform();

  setUpAll(() {
    PathProviderPlatform.instance = testPathProvider;
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    testPathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    testPathProvider.dispose();
  });

  testWidgets("session details shows player assignment backend state",
      (tester) async {
    final session = CaptureSession(
      sessionId: "session-players",
      sessionGuid: "guid-players",
      startTime: DateTime.utc(2026, 6, 8, 20, 55),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Players"), findsOneWidget);
    expect(find.text("Source: backend not configured"), findsOneWidget);
    expect(find.text("Player assignment unavailable"), findsOneWidget);
  });

  testWidgets("session details title prefers the session guid", (tester) async {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "backend-session-guid",
      startTime: DateTime.utc(2026, 6, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Session: backend-session-guid"), findsWidgets);
    expect(find.text("Session: legacy-session-id"), findsNothing);
  });

  testWidgets("session details metadata uses guid as primary session reference",
      (tester) async {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "backend-session-guid",
      startTime: DateTime.utc(2026, 6, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Session: backend-session-guid"), findsNWidgets(2));
    expect(find.text("Session ID: legacy-session-id"), findsNothing);
    expect(find.text("Legacy Session ID: legacy-session-id"), findsOneWidget);
  });

  testWidgets("load session action falls back to session id without guid",
      (tester) async {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      startTime: DateTime.utc(2026, 6, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    await tester.tap(find.byTooltip("Load Session"));
    await tester.pump();

    expect(
      find.textContaining("legacy-session-id"),
      findsWidgets,
    );
    expect(
      find.textContaining("Null check operator used on a null value"),
      findsNothing,
    );
  });

  testWidgets("upload confirm action reports missing restored metadata",
      (tester) async {
    final videoFile = File("${testPathProvider.documentsDir.path}/upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final session = CaptureSession(
      sessionId: "legacy-upload-id",
      sessionGuid: "missing-upload-guid",
      startTime: DateTime.utc(2026, 6, 9),
      capturedVideos: [
        CapturedVideo(
          videoPath: videoFile.path,
          slaveDeviceId: "upload-device",
          startRecordingDate: DateTime.utc(2026, 6, 9, 1),
          endRecordingDate: DateTime.utc(2026, 6, 9, 1, 1),
          receivedDate: DateTime.utc(2026, 6, 9, 1, 2),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pumpAndSettle();

    expect(find.text("Upload Unsent Media"), findsOneWidget);

    await tester.tap(find.text("Confirm"));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("missing-upload-guid"),
      findsWidgets,
    );
    expect(
      find.textContaining("Null check operator used on a null value"),
      findsNothing,
    );
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??= Directory.systemTemp.createTempSync(
      "session_details_screen_docs",
    );
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void resetDocumentsDir() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }

  void dispose() {
    resetDocumentsDir();
  }
}
