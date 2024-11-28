import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'log_service.dart';

class NetworkInfoService {
  static final NetworkInfo _networkInfo = NetworkInfo();
  static final Connectivity _connectivity = Connectivity();

  /// Get the SSID (Wi-Fi network name).
  static Future<String?> getSSID() async {
    try {
      final ssid = await _networkInfo.getWifiName();
      return ssid?.replaceAll('"', ''); // Remove quotes if present
    } catch (e) {
      LogService.instance.registerLog("Error getting SSID: $e");
      return null; // Return null if unable to get SSID
    }
  }

  /// Get the IP address of the device.
  static Future<String?> getIPAddress() async {
    try {
      // Try to get the Wi-Fi IP
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        return wifiIP;
      }

      // Fallback to general IP
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
      return null; // Return null if no valid IP found
    } catch (e) {
      LogService.instance.registerLog("Error getting IP address: $e");
      return null;
    }
  }

  /// Get the current network type (Wi-Fi or Mobile Data).
  static Future<String> getNetworkType() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      switch (connectivityResult) {
        case ConnectivityResult.wifi:
          final ssid = await getSSID();
          return ssid != null ? "Wi-Fi ($ssid)" : "Wi-Fi (Unknown)";
        case ConnectivityResult.mobile:
          return "Mobile Data";
        case ConnectivityResult.none:
        default:
          return "No Connection";
      }
    } catch (e) {
      LogService.instance.registerLog("Error determining network type: $e");
      return "Unknown";
    }
  }

  /// Get comprehensive network information including type and IP.
  static Future<Map<String, String?>> getNetworkInfo() async {
    final networkType = await getNetworkType();
    final ip = await getIPAddress();

    return {
      'networkType': networkType,
      'ip': ip ?? "Unknown IP",
    };
  }
}
