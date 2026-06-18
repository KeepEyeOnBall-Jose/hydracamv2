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

    // If the device ID doesn't exist or is unusable, generate and save a new one.
    if (deviceId == null || deviceId.trim().isEmpty) {
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
    } else if (Platform.isMacOS) {
      final MacOsDeviceInfo macosInfo = await deviceInfoPlugin.macOsInfo;
      return {
        "deviceId": await getOrCreateDeviceId(),
        "platform": "macOS",
        "computerName": macosInfo.computerName,
        "hostName": macosInfo.hostName,
        "model": macosInfo.model,
        "modelName": macosInfo.modelName,
        "arch": macosInfo.arch,
        "osRelease": macosInfo.osRelease,
        "version":
            "${macosInfo.majorVersion}.${macosInfo.minorVersion}.${macosInfo.patchVersion}",
        "activeCPUs": macosInfo.activeCPUs,
        "memorySize": macosInfo.memorySize,
        "cpuFrequency": macosInfo.cpuFrequency,
        "systemGUID": macosInfo.systemGUID,
      };
    } else {
      return {
        "deviceId": await getOrCreateDeviceId(),
        "platform": "Unsupported platform",
      };
    }
  }
}
