import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";

void main() {
  test("parses cameraModes and exposes them largest-first per camera", () {
    final capabilities = FixedCameraHlsCapabilities.fromMap({
      "platform": "android",
      "channelAvailable": true,
      "nativeRecorderImplemented": true,
      "cameraRecorderImplemented": true,
      "cameraIds": ["0", "1"],
      "cameraModes": [
        {
          "cameraId": "0",
          "width": 1920,
          "height": 1080,
          "maxFps": 30,
          "lensFacing": "back",
        },
        {
          "cameraId": "0",
          "width": 3840,
          "height": 2160,
          "maxFps": 30,
          "lensFacing": "back",
        },
        {
          "cameraId": "1",
          "width": 1280,
          "height": 720,
          "maxFps": 60,
          "lensFacing": "front",
        },
        "not-a-map",
      ],
    });

    expect(capabilities.cameraModes, hasLength(3));

    final cam0 = capabilities.modesForCamera("0");
    expect(cam0.map((m) => "${m.width}x${m.height}"), ["3840x2160", "1920x1080"]);

    final highest = capabilities.highestModeForCamera("0");
    expect(highest, isNotNull);
    expect(highest!.width, 3840);
    expect(highest.height, 2160);
    expect(highest.label, contains("3840x2160"));

    expect(capabilities.highestModeForCamera("1")!.maxFps, 60);
    expect(capabilities.highestModeForCamera("missing"), isNull);
  });

  test("camera mode value equality holds for dropdown selection", () {
    const a = FixedCameraHlsCameraMode(
      cameraId: "0",
      width: 1920,
      height: 1080,
      maxFps: 30,
      lensFacing: "back",
    );
    const b = FixedCameraHlsCameraMode(
      cameraId: "0",
      width: 1920,
      height: 1080,
      maxFps: 30,
      lensFacing: "back",
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });
}
