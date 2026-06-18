import "dart:io";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:network_info_plus/network_info_plus.dart";
import "linux_dbus_availability.dart";
import "log_service.dart";

enum NetworkReadinessBlockingReason {
  none,
  wifiDisabled,
  noLocalIp,
}

enum ConnectedDeviceNetworkStatus {
  ready,
  unknown,
  wrongNetwork,
}

extension ConnectedDeviceNetworkStatusLabel on ConnectedDeviceNetworkStatus {
  String get label {
    switch (this) {
      case ConnectedDeviceNetworkStatus.ready:
        return "Ready";
      case ConnectedDeviceNetworkStatus.unknown:
        return "Network details pending";
      case ConnectedDeviceNetworkStatus.wrongNetwork:
        return "Wrong network";
    }
  }
}

class NetworkSnapshot {
  final bool isWifiActive;
  final String? ipAddress;
  final String? ssid;
  final String? bssid;
  final String? gatewayIp;
  final String? subnetMask;
  final String? subnetSignature;
  final String source;
  final List<String> warnings;

  const NetworkSnapshot({
    required this.isWifiActive,
    required this.source,
    this.ipAddress,
    this.ssid,
    this.bssid,
    this.gatewayIp,
    this.subnetMask,
    this.subnetSignature,
    this.warnings = const [],
  });

  String? get effectiveSubnetSignature {
    final explicit = _normalizeBlank(subnetSignature);
    if (explicit != null) {
      return explicit;
    }

    final ip = _normalizeBlank(ipAddress);
    if (ip == null || !_isUsableIpv4(ip)) {
      return null;
    }

    final mask = _normalizeBlank(subnetMask);
    if (mask != null) {
      return _subnetSignatureFor(ip, mask);
    }

    if (_isPrivateOrLinkLocalIpv4(ip)) {
      return _fallbackPrivateSubnetSignature(ip);
    }

    return null;
  }

  bool get hasUsableLocalIp {
    final ip = _normalizeBlank(ipAddress);
    return ip != null && _isPrivateOrLinkLocalIpv4(ip);
  }

  Map<String, dynamic> toJson() {
    return {
      "isWifiActive": isWifiActive,
      "ipAddress": ipAddress,
      "ssid": ssid,
      "bssid": bssid,
      "gatewayIp": gatewayIp,
      "subnetMask": subnetMask,
      "subnetSignature": effectiveSubnetSignature,
      "source": source,
      "warnings": warnings,
    };
  }

  static NetworkSnapshot? tryFromJson(dynamic value) {
    if (value is! Map) {
      return null;
    }

    final warningsValue = value["warnings"];
    final warnings = warningsValue is List
        ? warningsValue.map((entry) => entry.toString()).toList()
        : const <String>[];

    return NetworkSnapshot(
      isWifiActive: value["isWifiActive"] == true,
      ipAddress: _stringFromJson(value["ipAddress"]),
      ssid: _stringFromJson(value["ssid"]),
      bssid: _stringFromJson(value["bssid"]),
      gatewayIp: _stringFromJson(value["gatewayIp"]),
      subnetMask: _stringFromJson(value["subnetMask"]),
      subnetSignature: _stringFromJson(value["subnetSignature"]),
      source: _stringFromJson(value["source"]) ?? "unknown",
      warnings: warnings,
    );
  }
}

class NetworkReadinessResult {
  final bool canUseLocalControl;
  final NetworkReadinessBlockingReason blockingReason;
  final String message;
  final NetworkSnapshot snapshot;

  const NetworkReadinessResult({
    required this.canUseLocalControl,
    required this.blockingReason,
    required this.message,
    required this.snapshot,
  });
}

// ignore: avoid_classes_with_only_static_members
class NetworkInfoService {
  static final NetworkInfo _networkInfo = NetworkInfo();
  static final Connectivity _connectivity = Connectivity();
  static const Duration _routeProbeTimeout = Duration(milliseconds: 800);
  static const List<(String, int)> _routeProbeTargets = [
    ("1.1.1.1", 53),
    ("8.8.8.8", 53),
  ];

  /// Get the SSID (Wi-Fi network name).
  static Future<String?> getSSID() async {
    final ssid = await _safeNetworkInfoPluginCall(
      "SSID",
      _networkInfo.getWifiName,
    );
    return _normalizeBlank(ssid?.replaceAll("\"", ""));
  }

  static Future<String?> getBSSID() async {
    return _normalizeBlank(await _safeNetworkInfoPluginCall(
      "BSSID",
      _networkInfo.getWifiBSSID,
    ));
  }

  /// Get the IP address of the device.
  static Future<String?> getIPAddress() async {
    try {
      final addresses = <InternetAddress>[];

      // Try to get the Wi-Fi IP. On iOS this can be a USB/link-local address,
      // so keep it as a candidate instead of returning it immediately.
      final wifiIP = await _safeNetworkInfoPluginCall(
        "Wi-Fi IP",
        _networkInfo.getWifiIP,
      );
      final normalizedWifiIp = _normalizeBlank(wifiIP);
      if (normalizedWifiIp != null && _isUsableIpv4(normalizedWifiIp)) {
        addresses.add(InternetAddress(normalizedWifiIp));
      }

      // Fallback to general IP. iOS can expose USB/link-local interfaces before
      // the actual LAN interface, so rank all candidates before choosing one.
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        addresses.addAll(interface.addresses);
      }

      return selectPreferredIpAddress(
        addresses,
        routeSelectedIpAddress: await _getRouteSelectedIpAddress(),
      );
    } catch (e) {
      LogService.instance.registerLog("Error getting IP address: $e");
      return null;
    }
  }

  static String? selectPreferredIpAddress(
    Iterable<InternetAddress> addresses, {
    String? routeSelectedIpAddress,
  }) {
    final routeIp = _normalizeBlank(routeSelectedIpAddress);
    if (routeIp != null && _isPrivateIpv4(routeIp)) {
      return routeIp;
    }

    String? privateIp;
    String? linkLocalIp;
    String? fallbackIp;

    for (final address in addresses) {
      if (address.type != InternetAddressType.IPv4 ||
          address.isLoopback ||
          !_isUsableIpv4(address.address)) {
        continue;
      }

      if (_isPrivateIpv4(address.address)) {
        privateIp ??= address.address;
      } else if (_isLinkLocalIpv4(address.address)) {
        linkLocalIp ??= address.address;
      } else {
        fallbackIp ??= address.address;
      }
    }

    if (routeIp != null && _isUsableIpv4(routeIp)) {
      fallbackIp ??= routeIp;
    }

    return privateIp ?? fallbackIp ?? linkLocalIp;
  }

  static Future<String?> _getRouteSelectedIpAddress() async {
    for (final (host, port) in _routeProbeTargets) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          host,
          port,
          timeout: _routeProbeTimeout,
        );
        final address = socket.address.address;
        if (_isUsableIpv4(address)) {
          return address;
        }
      } catch (_) {
        // Try the next route target.
      } finally {
        socket?.destroy();
      }
    }
    return null;
  }

  static Future<String?> getSubnetMask() async {
    return _normalizeBlank(await _safeNetworkInfoPluginCall(
      "subnet mask",
      _networkInfo.getWifiSubmask,
    ));
  }

  static Future<String?> getGatewayIp() async {
    return _normalizeBlank(await _safeNetworkInfoPluginCall(
      "gateway IP",
      _networkInfo.getWifiGatewayIP,
    ));
  }

  /// Get the current network type (Wi-Fi or Mobile Data).
  static Future<String> getNetworkType() async {
    try {
      final connectivityResults = await _safeConnectivityResults();
      if (connectivityResults.contains(ConnectivityResult.wifi)) {
        final ssid = await getSSID();
        return formatNetworkType(connectivityResults, ssid: ssid);
      }
      return formatNetworkType(connectivityResults);
    } catch (e) {
      LogService.instance.registerLog("Error determining network type: $e");
      return "Unknown";
    }
  }

  static String formatNetworkType(
    Iterable<ConnectivityResult> connectivityResults, {
    String? ssid,
  }) {
    final results = connectivityResults.toList();
    if (results.contains(ConnectivityResult.wifi)) {
      final normalizedSsid = _normalizeBlank(ssid);
      return normalizedSsid != null
          ? "Wi-Fi ($normalizedSsid)"
          : "Wi-Fi (enable location for SSID)";
    } else if (results.contains(ConnectivityResult.mobile)) {
      return "Mobile Data";
    } else if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return "No Connection";
    } else {
      return "Connected";
    }
  }

  static String formatSsidLabel(NetworkSnapshot? snapshot) {
    if (snapshot == null) {
      return "No network payload yet";
    }
    final ssid = _normalizeBlank(snapshot.ssid);
    if (ssid != null) {
      return ssid;
    }
    if (snapshot.isWifiActive) {
      return "Enable location for SSID";
    }
    return "Not on Wi-Fi";
  }

  static Stream<List<ConnectivityResult>> get connectivityChanges =>
      _connectivity.onConnectivityChanged;

  static Future<NetworkSnapshot> getCurrentSnapshot() async {
    final connectivityResults = await _safeConnectivityResults();
    final isWifiActive = connectivityResults.contains(ConnectivityResult.wifi);
    final ssid = await getSSID();
    final bssid = await getBSSID();
    final ipAddress = await getIPAddress();
    final subnetMask = await getSubnetMask();
    final gatewayIp = await getGatewayIp();
    final warnings = <String>[];

    if (isWifiActive && ssid == null) {
      warnings.add(
        "SSID unavailable; grant location permission and enable Location Services.",
      );
    }

    final snapshot = NetworkSnapshot(
      isWifiActive: isWifiActive,
      ipAddress: ipAddress,
      ssid: ssid,
      bssid: bssid,
      gatewayIp: gatewayIp,
      subnetMask: subnetMask,
      source: "device",
      warnings: warnings,
    );

    return NetworkSnapshot(
      isWifiActive: snapshot.isWifiActive,
      ipAddress: snapshot.ipAddress,
      ssid: snapshot.ssid,
      bssid: snapshot.bssid,
      gatewayIp: snapshot.gatewayIp,
      subnetMask: snapshot.subnetMask,
      subnetSignature: snapshot.effectiveSubnetSignature,
      source: snapshot.source,
      warnings: snapshot.warnings,
    );
  }

  static NetworkReadinessResult evaluateLocalControlReadiness(
    NetworkSnapshot snapshot, {
    bool requireWifi = true,
  }) {
    if (requireWifi && !snapshot.isWifiActive) {
      return NetworkReadinessResult(
        canUseLocalControl: false,
        blockingReason: NetworkReadinessBlockingReason.wifiDisabled,
        message: "Wi-Fi is not ready. Enable Wi-Fi and join the HydraCam LAN.",
        snapshot: snapshot,
      );
    }

    if (!snapshot.hasUsableLocalIp) {
      return NetworkReadinessResult(
        canUseLocalControl: false,
        blockingReason: NetworkReadinessBlockingReason.noLocalIp,
        message:
            "No local network IP found. Join the same Wi-Fi or hotspot as the master.",
        snapshot: snapshot,
      );
    }

    final warnings = <String>[
      ...snapshot.warnings,
      if (requireWifi && _normalizeBlank(snapshot.ssid) == null)
        "SSID unavailable; grant location permission and enable Location Services. "
            "Using local IP/subnet checks.",
    ];
    final message = warnings.isEmpty
        ? "Local network ready."
        : "Local network ready. ${warnings.join(" ")}";

    return NetworkReadinessResult(
      canUseLocalControl: true,
      blockingReason: NetworkReadinessBlockingReason.none,
      message: message,
      snapshot: snapshot,
    );
  }

  static ConnectedDeviceNetworkStatus compareDeviceNetwork({
    required NetworkSnapshot masterSnapshot,
    required NetworkSnapshot? deviceSnapshot,
    String? socketRemoteIp,
  }) {
    if (deviceSnapshot == null ||
        !masterSnapshot.hasUsableLocalIp ||
        !deviceSnapshot.hasUsableLocalIp) {
      return ConnectedDeviceNetworkStatus.unknown;
    }

    final masterSubnet = masterSnapshot.effectiveSubnetSignature;
    final deviceSubnet = deviceSnapshot.effectiveSubnetSignature;
    if (masterSubnet != null && deviceSubnet != null) {
      if (masterSubnet != deviceSubnet) {
        return ConnectedDeviceNetworkStatus.wrongNetwork;
      }
    }

    final remoteIp = _normalizeBlank(socketRemoteIp);
    if (remoteIp != null && masterSubnet != null) {
      if (!_isIpInSubnetSignature(remoteIp, masterSubnet)) {
        return ConnectedDeviceNetworkStatus.wrongNetwork;
      }
    }

    if (masterSubnet != null && deviceSubnet != null) {
      return ConnectedDeviceNetworkStatus.ready;
    }

    if (remoteIp != null && masterSubnet != null) {
      return ConnectedDeviceNetworkStatus.ready;
    }

    final masterBssid = _normalizeBlank(masterSnapshot.bssid)?.toLowerCase();
    final deviceBssid = _normalizeBlank(deviceSnapshot.bssid)?.toLowerCase();
    if (masterBssid != null &&
        deviceBssid != null &&
        masterBssid == deviceBssid) {
      return ConnectedDeviceNetworkStatus.ready;
    }

    final masterGateway = _normalizeBlank(masterSnapshot.gatewayIp);
    final deviceGateway = _normalizeBlank(deviceSnapshot.gatewayIp);
    if (masterGateway != null &&
        deviceGateway != null &&
        masterGateway == deviceGateway) {
      return ConnectedDeviceNetworkStatus.ready;
    }

    return ConnectedDeviceNetworkStatus.unknown;
  }

  /// Get comprehensive network information including type and IP.
  static Future<Map<String, String?>> getNetworkInfo() async {
    final networkType = await getNetworkType();
    final ip = await getIPAddress();

    return {
      "networkType": networkType,
      "ip": ip ?? "Unknown IP",
    };
  }

  static Future<List<ConnectivityResult>> _safeConnectivityResults() async {
    if (LinuxDbusAvailability.shouldSkipSystemBusPlugins) {
      LogService.instance.registerLog(
        "Skipping connectivity plugin on linux because "
        "${LinuxDbusAvailability.systemBusSocketPath} is unavailable.",
      );
      return const [ConnectivityResult.none];
    }

    try {
      return await _connectivity.checkConnectivity();
    } catch (e) {
      LogService.instance.registerLog("Error checking connectivity: $e");
      return const [ConnectivityResult.none];
    }
  }

  @visibleForTesting
  static bool shouldSkipConnectivityPluginForTesting({
    required bool isLinux,
    required bool hasSystemBusSocket,
  }) {
    return LinuxDbusAvailability.shouldSkipSystemBusPluginsFor(
      isLinux: isLinux,
      hasSystemBusSocket: hasSystemBusSocket,
    );
  }

  static Future<String?> _safeNetworkInfoPluginCall(
    String label,
    Future<String?> Function() load,
  ) async {
    if (LinuxDbusAvailability.shouldSkipSystemBusPlugins) {
      LogService.instance.registerLog(
        "Skipping network info plugin for $label on linux because "
        "${LinuxDbusAvailability.systemBusSocketPath} is unavailable.",
      );
      return null;
    }

    try {
      return await load();
    } catch (e) {
      LogService.instance.registerLog("Error getting $label: $e");
      return null;
    }
  }
}

String? _stringFromJson(dynamic value) {
  if (value == null) {
    return null;
  }
  return _normalizeBlank(value.toString());
}

String? _normalizeBlank(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed == "0.0.0.0" ||
      trimmed.toLowerCase() == "null") {
    return null;
  }
  return trimmed;
}

bool _isUsableIpv4(String value) {
  final octets = _parseIpv4(value);
  if (octets == null) {
    return false;
  }
  return !(octets[0] == 0 || octets[0] == 127);
}

bool _isPrivateOrLinkLocalIpv4(String value) {
  return _isPrivateIpv4(value) || _isLinkLocalIpv4(value);
}

bool _isPrivateIpv4(String value) {
  final octets = _parseIpv4(value);
  if (octets == null || !_isUsableIpv4(value)) {
    return false;
  }
  if (octets[0] == 10 || octets[0] == 192 && octets[1] == 168) {
    return true;
  }
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true;
  }
  return false;
}

bool _isLinkLocalIpv4(String value) {
  final octets = _parseIpv4(value);
  if (octets == null || !_isUsableIpv4(value)) {
    return false;
  }
  return octets[0] == 169 && octets[1] == 254;
}

List<int>? _parseIpv4(String value) {
  final parts = value.split(".");
  if (parts.length != 4) {
    return null;
  }

  final octets = <int>[];
  for (final part in parts) {
    final parsed = int.tryParse(part);
    if (parsed == null || parsed < 0 || parsed > 255) {
      return null;
    }
    octets.add(parsed);
  }
  return octets;
}

String? _subnetSignatureFor(String ipAddress, String subnetMask) {
  final ip = _ipv4ToInt(ipAddress);
  final mask = _ipv4ToInt(subnetMask);
  if (ip == null || mask == null) {
    return null;
  }
  final prefix = _prefixLength(mask);
  if (prefix == null) {
    return null;
  }
  final network = ip & mask;
  return "${_intToIpv4(network)}/$prefix";
}

String? _fallbackPrivateSubnetSignature(String ipAddress) {
  final octets = _parseIpv4(ipAddress);
  if (octets == null) {
    return null;
  }
  return "${octets[0]}.${octets[1]}.${octets[2]}.0/24";
}

int? _ipv4ToInt(String value) {
  final octets = _parseIpv4(value);
  if (octets == null) {
    return null;
  }
  return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
}

String _intToIpv4(int value) {
  final first = value >> 24 & 0xff;
  final second = value >> 16 & 0xff;
  final third = value >> 8 & 0xff;
  final fourth = value & 0xff;
  return "$first.$second.$third.$fourth";
}

int? _prefixLength(int mask) {
  var seenZero = false;
  var prefix = 0;
  for (var bit = 31; bit >= 0; bit--) {
    final isSet = mask & (1 << bit) != 0;
    if (isSet && seenZero) {
      return null;
    }
    if (isSet) {
      prefix++;
    } else {
      seenZero = true;
    }
  }
  return prefix;
}

bool _isIpInSubnetSignature(String ipAddress, String subnetSignature) {
  final parts = subnetSignature.split("/");
  if (parts.length != 2) {
    return false;
  }
  final network = _ipv4ToInt(parts[0]);
  final ip = _ipv4ToInt(ipAddress);
  final prefix = int.tryParse(parts[1]);
  if (network == null || ip == null || prefix == null) {
    return false;
  }
  if (prefix < 0 || prefix > 32) {
    return false;
  }
  final mask = prefix == 0 ? 0 : 0xffffffff << (32 - prefix) & 0xffffffff;
  return ip & mask == network & mask;
}
