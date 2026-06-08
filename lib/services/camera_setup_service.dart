import "package:camera/camera.dart";
import "package:flutter/foundation.dart";

import "../models/capture_context_metadata.dart";
import "device_level_service.dart";
import "device_service.dart";

class CameraSetupService {
  CameraSetupService._internal();

  static final CameraSetupService instance = CameraSetupService._internal();

  CameraPerspectiveMetadata _perspective = CameraPerspectiveMetadata.unknown;
  DeviceLevelReading _latestReading = DeviceLevelReading.unavailable();

  final ValueNotifier<CameraPerspectiveMetadata> perspectiveNotifier =
      ValueNotifier(CameraPerspectiveMetadata.unknown);
  final ValueNotifier<DeviceLevelReading> levelReadingNotifier =
      ValueNotifier(DeviceLevelReading.unavailable());

  CameraPerspectiveMetadata get perspective => _perspective;
  DeviceLevelReading get latestReading => _latestReading;

  void setPerspective(CameraPerspectiveMetadata perspective) {
    _perspective = perspective;
    perspectiveNotifier.value = perspective;
  }

  void updateLevelReading(DeviceLevelReading reading) {
    _latestReading = reading;
    levelReadingNotifier.value = reading;
  }

  Future<MediaCaptureContext> buildCaptureContext({
    required CameraController? controller,
    required String? videoCaptureProfile,
  }) async {
    final deviceId = await DeviceIdService.getOrCreateDeviceId();
    final camera = controller?.description;
    return MediaCaptureContext(
      perspective: _perspective,
      level: _latestReading.toMetadata(),
      cameraName: camera?.name,
      cameraLensDirection: camera?.lensDirection.name,
      cameraSensorOrientation: camera?.sensorOrientation,
      videoCaptureProfile: videoCaptureProfile,
      deviceId: deviceId,
    );
  }

  Map<String, dynamic> buildSetupStatusPayload() {
    return {
      "cameraPerspectiveId": _perspective.cameraPerspectiveId,
      "cameraPerspectiveLabel": _perspective.cameraPerspectiveLabel,
      "isLevel": _latestReading.isLevel,
      "sensorAvailable": _latestReading.sensorAvailable,
      if (_latestReading.rollDegrees != null)
        "rollDegrees": _latestReading.rollDegrees,
      if (_latestReading.pitchDegrees != null)
        "pitchDegrees": _latestReading.pitchDegrees,
    };
  }

  @visibleForTesting
  void resetForTest() {
    setPerspective(CameraPerspectiveMetadata.unknown);
    updateLevelReading(DeviceLevelReading.unavailable());
  }
}
