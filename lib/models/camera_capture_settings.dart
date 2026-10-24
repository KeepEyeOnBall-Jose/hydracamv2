import "package:camera/camera.dart";

enum LensPreference {
  autoBack("autoBack", "Auto back camera"),
  ultraWide("ultraWide", "Ultra Wide (0.5x)"),
  wide("wide", "Wide (1x)"),
  telephoto("telephoto", "Telephoto"),
  front("front", "Front");

  const LensPreference(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static LensPreference fromStorageValue(String? value) {
    return LensPreference.values.firstWhere(
      (preference) => preference.storageValue == value,
      orElse: () => LensPreference.autoBack,
    );
  }

  bool matches(CameraDescription camera) {
    return switch (this) {
      LensPreference.autoBack =>
        camera.lensDirection == CameraLensDirection.back,
      LensPreference.ultraWide => camera.lensType == CameraLensType.ultraWide,
      LensPreference.wide => camera.lensType == CameraLensType.wide ||
          (camera.lensDirection == CameraLensDirection.back &&
              camera.lensType == CameraLensType.unknown),
      LensPreference.telephoto => camera.lensType == CameraLensType.telephoto,
      LensPreference.front => camera.lensDirection == CameraLensDirection.front,
    };
  }
}

enum VideoCaptureProfile {
  dataSaver480p30(
    "dataSaver480p30",
    "480p at 30 fps",
    "Small files for diagnostics.",
    ResolutionPreset.medium,
    30,
  ),
  compat720p30(
    "compat720p30",
    "720p at 30 fps",
    "Broad device support.",
    ResolutionPreset.high,
    30,
  ),
  standard1080p30(
    "standard1080p30",
    "1080p at 30 fps",
    "Default balance of quality and storage.",
    ResolutionPreset.veryHigh,
    30,
  ),
  sport1080p60(
    "sport1080p60",
    "1080p at 60 fps",
    "Recommended for squash when the phone supports it.",
    ResolutionPreset.veryHigh,
    60,
  ),
  detail4k30(
    "detail4k30",
    "4K at 30 fps",
    "Higher detail for analysis with larger files.",
    ResolutionPreset.ultraHigh,
    30,
  ),
  pro4k60(
    "pro4k60",
    "4K at 60 fps",
    "Highest target profile; verify support on each device.",
    ResolutionPreset.ultraHigh,
    60,
  );

  const VideoCaptureProfile(
    this.storageValue,
    this.label,
    this.description,
    this.resolutionPreset,
    this.framesPerSecond,
  );

  final String storageValue;
  final String label;
  final String description;
  final ResolutionPreset resolutionPreset;
  final int framesPerSecond;

  String get targetLabel {
    final resolution = switch (resolutionPreset) {
      ResolutionPreset.medium => "480p",
      ResolutionPreset.high => "720p",
      ResolutionPreset.veryHigh => "1080p",
      ResolutionPreset.ultraHigh => "4K",
      ResolutionPreset.max => "maximum",
      ResolutionPreset.low => "low",
    };
    return "$resolution at $framesPerSecond fps";
  }

  static VideoCaptureProfile fromStorageValue(String? value) {
    return VideoCaptureProfile.values.firstWhere(
      (profile) => profile.storageValue == value,
      orElse: () => VideoCaptureProfile.standard1080p30,
    );
  }

  static VideoCaptureProfile fromLegacyCameraQuality(String? quality) {
    return switch (quality) {
      "low" => VideoCaptureProfile.dataSaver480p30,
      "medium" => VideoCaptureProfile.compat720p30,
      _ => VideoCaptureProfile.standard1080p30,
    };
  }
}

/// Shutter presets for measurable ball streaks. A manual preset locks exposure
/// time, ISO (metered once from auto exposure), white balance and focus for the
/// whole clip; [auto] leaves the camera on auto exposure for comparison.
enum ExposurePreset {
  auto("auto", "Auto exposure", null),
  shutter1_30("shutter1_30", "1/30 s shutter", 33333333),
  shutter1_60("shutter1_60", "1/60 s shutter", 16666667),
  shutter1_120("shutter1_120", "1/120 s shutter", 8333333);

  const ExposurePreset(this.storageValue, this.label, this.exposureTimeNs);

  static const ExposurePreset defaultPreset = ExposurePreset.shutter1_60;

  final String storageValue;
  final String label;

  /// Requested sensor exposure time; null for [auto].
  final int? exposureTimeNs;

  bool get isManual => exposureTimeNs != null;

  static ExposurePreset fromStorageValue(String? value) {
    return ExposurePreset.values.firstWhere(
      (preset) => preset.storageValue == value,
      orElse: () => defaultPreset,
    );
  }
}

class CameraLensLabels {
  const CameraLensLabels._();

  static String describe(CameraDescription camera) {
    return switch (camera.lensType) {
      CameraLensType.ultraWide => "Ultra Wide (0.5x)",
      CameraLensType.wide => "Wide (1x)",
      CameraLensType.telephoto => "Telephoto",
      CameraLensType.unknown => _describeUnknownLens(camera),
    };
  }

  static String _describeUnknownLens(CameraDescription camera) {
    return switch (camera.lensDirection) {
      CameraLensDirection.front => "Front camera ${camera.name}",
      CameraLensDirection.back => "Back camera ${camera.name}",
      CameraLensDirection.external => "External camera ${camera.name}",
    };
  }
}
