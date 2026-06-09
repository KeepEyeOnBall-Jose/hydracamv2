import "../models/camera_capture_settings.dart";

typedef CameraDeviceInfoProvider = Future<Map<String, dynamic>> Function();

class CameraCompatibilityPolicy {
  const CameraCompatibilityPolicy({
    this.profileOverride,
    this.usePresetDefaultFps = false,
    this.retryTimedOutPhotoAfterReinitialize = false,
    this.reason,
  });

  static const none = CameraCompatibilityPolicy();

  final VideoCaptureProfile? profileOverride;
  final bool usePresetDefaultFps;
  final bool retryTimedOutPhotoAfterReinitialize;
  final String? reason;

  bool get isActive =>
      profileOverride != null ||
      usePresetDefaultFps ||
      retryTimedOutPhotoAfterReinitialize;

  VideoCaptureProfile resolveProfile(VideoCaptureProfile requestedProfile) {
    return profileOverride ?? requestedProfile;
  }
}

class CameraCompatibilityPolicyResolver {
  const CameraCompatibilityPolicyResolver._();

  static CameraCompatibilityPolicy fromDeviceInfo(
      Map<String, dynamic>? deviceInfo) {
    if (_isSamsungS7Edge(deviceInfo)) {
      return const CameraCompatibilityPolicy(
        usePresetDefaultFps: true,
        retryTimedOutPhotoAfterReinitialize: true,
        reason: "Samsung S7 edge compatibility mode: preserve requested "
            "resolution with preset-default fps",
      );
    }

    return CameraCompatibilityPolicy.none;
  }

  static bool _isSamsungS7Edge(Map<String, dynamic>? deviceInfo) {
    if (deviceInfo == null) {
      return false;
    }

    final manufacturer =
        (deviceInfo["manufacturer"] ?? deviceInfo["brand"] ?? "")
            .toString()
            .toLowerCase();
    final model = (deviceInfo["model"] ?? "").toString().toUpperCase();

    return manufacturer.contains("samsung") &&
        (model.contains("SM-G935") || model.contains("SAMSUNG-SM-G935"));
  }
}
