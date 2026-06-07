import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/camera_hardware_metadata_service.dart";

void main() {
  test("camera metadata formats focal length and zoom details", () {
    final metadata = CameraHardwareMetadata.fromMap({
      "cameraId": "0",
      "focalLengths": [4.2, 6],
      "maxDigitalZoom": 8,
    });

    expect(metadata?.detailText, "4.2mm, 6.0mm • max zoom 8.0x");
  });

  test("camera metadata tolerates missing optional values", () {
    final metadata = CameraHardwareMetadata.fromMap({"cameraId": "1"});

    expect(metadata?.detailText, isNull);
  });
}
