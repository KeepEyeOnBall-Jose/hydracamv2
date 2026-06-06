import "dart:io";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";
import "package:device_info_plus/device_info_plus.dart";
import "log_service.dart";

// ignore: avoid_classes_with_only_static_members
class DeviceIdService {
  static const String _deviceIdKey = "device_id";

  /// Get the device ID or create a new one if it doesn't exist.
  static Future<String> getOrCreateDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    // If the device ID doesn't exist, generate a new one and save it.
    if (deviceId == null) {
      deviceId = const Uuid().v4(); // Generate a new unique ID (UUID v4).
      await prefs.setString(_deviceIdKey, deviceId);
      LogService.instance.registerLog("Generated new Device ID: $deviceId");
    } else {
      LogService.instance
          .registerLog("Retrieved existing Device ID: $deviceId");
    }

    return deviceId;
  }

  /// Get detailed information about the current device.
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
      return {
        "deviceId": await getOrCreateDeviceId(),
        "brand": androidInfo.brand,
        "model": androidInfo.model,
        "manufacturer": androidInfo.manufacturer,
        "version.release": androidInfo.version.release,
        "version.sdkInt": androidInfo.version.sdkInt,
        "isPhysicalDevice": androidInfo.isPhysicalDevice,
      };
    } else if (Platform.isIOS) {
      final IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
      return {
        "deviceId": await getOrCreateDeviceId(),
        "name": iosInfo.name,
        "model": iosInfo.model,
        "systemName": iosInfo.systemName,
        "systemVersion": iosInfo.systemVersion,
        "isPhysicalDevice": iosInfo.isPhysicalDevice,
        "identifierForVendor": iosInfo.identifierForVendor,
      };
    } else {
      return {
        "deviceId": await getOrCreateDeviceId(),
        "platform": "Unsupported platform",
      };
    }
  }
}
