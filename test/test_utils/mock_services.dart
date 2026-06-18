import "package:mocktail/mocktail.dart";
import "package:hydracam/services/camera_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/master/master_server.dart";

/// Mock classes for testing using mocktail

class MockCameraService extends Mock implements CameraService {}

class MockStorageService extends Mock implements StorageService {}

class MockSessionManager extends Mock implements SessionManager {}

class MockUploaderService extends Mock implements UploaderService {}

class MockHydraCamApiService extends Mock implements HydraCamApiService {}

class MockMasterServer extends Mock implements MasterServer {}

/// Fake classes for simple data structures

class FakeStorageService extends Fake implements StorageService {
  FakeStorageService({
    this.isRecordingBlockedValue = false,
    this.lowStorageThresholdValue = 1.5,
    this.criticalStorageThresholdValue = 0.5,
  });

  bool isRecordingBlockedValue;
  final double lowStorageThresholdValue;
  final double criticalStorageThresholdValue;

  @override
  bool get isRecordingBlocked => isRecordingBlockedValue;

  double get lowStorageThreshold => lowStorageThresholdValue;

  double get criticalStorageThreshold => criticalStorageThresholdValue;

  @override
  void dispose() {}
}

class FakeSessionManager extends Fake implements SessionManager {
  String? _sessionGuid;
  bool _isSessionActive = false;

  @override
  String? get sessionGuid => _sessionGuid;

  @override
  bool get isSessionActive => _isSessionActive;

  @override
  void startSession(
    String guid,
    String? id, {
    required String deviceType,
    bool debugSession = false,
    int? serviceNumericId,
  }) {
    _sessionGuid = guid;
    _isSessionActive = true;
  }

  @override
  Future<void> endSession() async {
    _sessionGuid = null;
    _isSessionActive = false;
  }
}
