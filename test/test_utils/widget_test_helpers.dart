import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";
import "package:hydracam/services/camera_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/services/session_manager.dart";
import "mock_services.dart";

/// Helper functions for widget testing

/// Wraps a widget with MaterialApp and necessary providers for testing
Widget createTestableWidget({
  required Widget child,
  CameraService? cameraService,
  StorageService? storageService,
  SessionManager? sessionManager,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<CameraService>.value(
          value: cameraService ?? MockCameraService(),
        ),
        Provider<StorageService>.value(
          value: storageService ?? FakeStorageService(),
        ),
        ChangeNotifierProvider<SessionManager>.value(
          value: sessionManager ?? FakeSessionManager(),
        ),
      ],
      child: child,
    ),
  );
}

/// Pumps a widget wrapped with providers
Future<void> pumpTestableWidget(
  WidgetTester tester, {
  required Widget child,
  CameraService? cameraService,
  StorageService? storageService,
  SessionManager? sessionManager,
}) async {
  await tester.pumpWidget(
    createTestableWidget(
      child: child,
      cameraService: cameraService,
      storageService: storageService,
      sessionManager: sessionManager,
    ),
  );
}
