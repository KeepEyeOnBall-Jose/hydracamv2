import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/device_service.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel deviceInfoChannel = MethodChannel(
    "dev.fluttercommunity.plus/device_info",
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceInfoChannel, null);
  });

  group("DeviceIdService", () {
    test("regenerates blank stored device IDs", () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        "device_id": "   ",
      });

      final deviceId = await DeviceIdService.getOrCreateDeviceId();
      final prefs = await SharedPreferences.getInstance();

      expect(deviceId.trim(), isNotEmpty);
      expect(deviceId, isNot("   "));
      expect(prefs.getString("device_id"), deviceId);
    });

    test("preserves existing nonblank device IDs", () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        "device_id": "existing-device-id",
      });

      final deviceId = await DeviceIdService.getOrCreateDeviceId();
      final prefs = await SharedPreferences.getInstance();

      expect(deviceId, "existing-device-id");
      expect(prefs.getString("device_id"), "existing-device-id");
    });

    test("reports native macOS device info instead of unsupported platform",
        () async {
      if (!Platform.isMacOS) {
        return;
      }

      SharedPreferences.setMockInitialValues(<String, Object>{});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceInfoChannel, (call) async {
        expect(call.method, "getDeviceInfo");
        return <String, dynamic>{
          "computerName": "Hydra Mac",
          "hostName": "hydra-mac.local",
          "arch": "arm64",
          "model": "Mac16,2",
          "modelName": "iMac (24-inch, 2024)",
          "kernelVersion": "Darwin Kernel Version",
          "osRelease": "25.5.0",
          "majorVersion": 15,
          "minorVersion": 5,
          "patchVersion": 0,
          "activeCPUs": 8,
          "memorySize": 17179869184,
          "cpuFrequency": 2400000000,
          "systemGUID": "mac-guid",
        };
      });

      final Map<String, dynamic> deviceInfo =
          await DeviceIdService.getDeviceInfo();

      expect(deviceInfo["platform"], "macOS");
      expect(deviceInfo["model"], "Mac16,2");
      expect(deviceInfo["modelName"], "iMac (24-inch, 2024)");
      expect(deviceInfo["platform"], isNot("Unsupported platform"));
    });
  });
}
