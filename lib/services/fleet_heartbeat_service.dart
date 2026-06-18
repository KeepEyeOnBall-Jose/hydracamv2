import "package:battery_plus/battery_plus.dart";
import "package:disk_space_plus/disk_space_plus.dart";
import "package:package_info_plus/package_info_plus.dart";

import "device_service.dart";
import "log_service.dart";
import "network_info_service.dart";

enum FleetHeartbeatHealth {
  ready,
  warning,
  blocked;

  String get label => name;
}

class FleetPackageDetails {
  final String appVersion;
  final String buildNumber;
  final String packageName;

  const FleetPackageDetails({
    required this.appVersion,
    required this.buildNumber,
    required this.packageName,
  });

  static const FleetPackageDetails unknown = FleetPackageDetails(
    appVersion: "unknown",
    buildNumber: "unknown",
    packageName: "unknown",
  );

  static FleetPackageDetails fromPackageInfo(PackageInfo packageInfo) {
    return FleetPackageDetails(
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      packageName: packageInfo.packageName,
    );
  }
}

class FleetBatteryReading {
  final int? levelPercent;
  final String? state;

  const FleetBatteryReading({
    this.levelPercent,
    this.state,
  });
}

class FleetHeartbeatSnapshot {
  static const int currentSchemaVersion = 1;
  static const List<String> defaultSupportedCommands = [
    "report_status",
    "set_role",
    "start_session",
    "stop_session",
    "take_photo",
    "start_recording",
    "stop_recording",
    "capture_diagnostic_screenshot",
    "upload_logs",
    "restart_app",
  ];

  final int schemaVersion;
  final DateTime generatedAtUtc;
  final String deviceId;
  final String labLabel;
  final String fleetMode;
  final String appVersion;
  final String buildNumber;
  final String packageName;
  final String runtimeRole;
  final NetworkSnapshot networkSnapshot;
  final bool localControlReady;
  final String localControlReadinessMessage;
  final int? batteryLevelPercent;
  final String? batteryState;
  final double? freeStorageGb;
  final bool isRecording;
  final String? activeSessionGuid;
  final int uploadQueueDepth;
  final Map<String, dynamic> deviceInfo;
  final List<String> warnings;
  final List<String> blockers;
  final List<String> supportedCommands;

  const FleetHeartbeatSnapshot._({
    required this.schemaVersion,
    required this.generatedAtUtc,
    required this.deviceId,
    required this.labLabel,
    required this.fleetMode,
    required this.appVersion,
    required this.buildNumber,
    required this.packageName,
    required this.runtimeRole,
    required this.networkSnapshot,
    required this.localControlReady,
    required this.localControlReadinessMessage,
    required this.batteryLevelPercent,
    required this.batteryState,
    required this.freeStorageGb,
    required this.isRecording,
    required this.activeSessionGuid,
    required this.uploadQueueDepth,
    required this.deviceInfo,
    required this.warnings,
    required this.blockers,
    required this.supportedCommands,
  });

  FleetHeartbeatHealth get health {
    if (blockers.isNotEmpty) {
      return FleetHeartbeatHealth.blocked;
    }
    if (warnings.isNotEmpty) {
      return FleetHeartbeatHealth.warning;
    }
    return FleetHeartbeatHealth.ready;
  }

  static FleetHeartbeatSnapshot build({
    required String deviceId,
    required String labLabel,
    required DateTime generatedAtUtc,
    required String appVersion,
    required String buildNumber,
    required String packageName,
    required String runtimeRole,
    required String fleetMode,
    required NetworkSnapshot networkSnapshot,
    required int? batteryLevelPercent,
    required String? batteryState,
    required double? freeStorageGb,
    required bool isRecording,
    required int uploadQueueDepth,
    String? activeSessionGuid,
    Map<String, dynamic> deviceInfo = const {},
    List<String> supportedCommands = defaultSupportedCommands,
    List<String> additionalWarnings = const [],
  }) {
    final networkReadiness =
        NetworkInfoService.evaluateLocalControlReadiness(networkSnapshot);
    final blockers = <String>[];
    final warnings = <String>[];

    if (!networkReadiness.canUseLocalControl) {
      blockers.add(_networkBlockerCode(networkReadiness.blockingReason));
    }

    for (final warning in networkSnapshot.warnings) {
      final warningCode = _networkWarningCode(warning);
      if (warningCode != null) {
        warnings.add(warningCode);
      }
    }
    if (networkReadiness.canUseLocalControl &&
        networkReadiness.message.contains("SSID unavailable")) {
      warnings.add("network:ssid-unavailable");
    }
    for (final warning in additionalWarnings) {
      final normalized = warning.trim();
      if (normalized.isNotEmpty) {
        warnings.add(normalized);
      }
    }

    final batteryLevel = batteryLevelPercent;
    if (batteryLevel == null) {
      warnings.add("battery:unknown");
    } else if (batteryLevel <= 10) {
      blockers.add("battery:critical");
    } else if (batteryLevel < 25) {
      warnings.add("battery:low");
    }

    final storageGb = freeStorageGb;
    if (storageGb == null) {
      warnings.add("storage:unknown");
    } else if (storageGb < 0.5) {
      blockers.add("storage:critical");
    } else if (storageGb < 2.0) {
      warnings.add("storage:low");
    }

    return FleetHeartbeatSnapshot._(
      schemaVersion: currentSchemaVersion,
      generatedAtUtc: generatedAtUtc.toUtc(),
      deviceId: deviceId,
      labLabel: labLabel,
      fleetMode: fleetMode,
      appVersion: appVersion,
      buildNumber: buildNumber,
      packageName: packageName,
      runtimeRole: runtimeRole,
      networkSnapshot: networkSnapshot,
      localControlReady: networkReadiness.canUseLocalControl,
      localControlReadinessMessage: networkReadiness.message,
      batteryLevelPercent: batteryLevelPercent,
      batteryState: batteryState,
      freeStorageGb: freeStorageGb,
      isRecording: isRecording,
      activeSessionGuid: activeSessionGuid,
      uploadQueueDepth: uploadQueueDepth,
      deviceInfo: Map<String, dynamic>.unmodifiable(deviceInfo),
      warnings: List<String>.unmodifiable(warnings.toSet()),
      blockers: List<String>.unmodifiable(blockers.toSet()),
      supportedCommands: List<String>.unmodifiable(supportedCommands),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "schemaVersion": schemaVersion,
      "generatedAtUtc": generatedAtUtc.toIso8601String(),
      "deviceId": deviceId,
      "labLabel": labLabel,
      "fleetMode": fleetMode,
      "health": health.label,
      "app": {
        "version": appVersion,
        "buildNumber": buildNumber,
        "packageName": packageName,
      },
      "device": deviceInfo,
      "role": {
        "current": runtimeRole,
        "recording": isRecording,
        "activeSessionGuid": activeSessionGuid,
      },
      "network": {
        ...networkSnapshot.toJson(),
        "localControlReady": localControlReady,
        "readinessMessage": localControlReadinessMessage,
      },
      "battery": {
        "levelPercent": batteryLevelPercent,
        "state": batteryState,
      },
      "storage": {
        "freeGb": freeStorageGb,
      },
      "upload": {
        "queueDepth": uploadQueueDepth,
      },
      "warnings": warnings,
      "blockers": blockers,
      "supportedCommands": supportedCommands,
    };
  }

  static String _networkBlockerCode(
    NetworkReadinessBlockingReason blockingReason,
  ) {
    switch (blockingReason) {
      case NetworkReadinessBlockingReason.wifiDisabled:
        return "network:wifi-disabled";
      case NetworkReadinessBlockingReason.noLocalIp:
        return "network:no-local-ip";
      case NetworkReadinessBlockingReason.none:
        return "network:unknown";
    }
  }

  static String? _networkWarningCode(String warning) {
    if (warning.contains("SSID unavailable")) {
      return "network:ssid-unavailable";
    }
    if (warning.contains("Network snapshot unavailable")) {
      return "network:unavailable";
    }
    return null;
  }
}

typedef FleetDeviceIdProvider = Future<String> Function();
typedef FleetDeviceInfoProvider = Future<Map<String, dynamic>> Function();
typedef FleetNetworkSnapshotProvider = Future<NetworkSnapshot> Function();
typedef FleetPackageInfoProvider = Future<FleetPackageDetails> Function();
typedef FleetBatteryReadingProvider = Future<FleetBatteryReading?> Function();
typedef FleetFreeStorageGbProvider = Future<double?> Function();
typedef FleetClock = DateTime Function();

class FleetHeartbeatCollector {
  final FleetDeviceIdProvider _deviceIdProvider;
  final FleetDeviceInfoProvider _deviceInfoProvider;
  final FleetNetworkSnapshotProvider _networkSnapshotProvider;
  final FleetPackageInfoProvider _packageInfoProvider;
  final FleetBatteryReadingProvider _batteryReadingProvider;
  final FleetFreeStorageGbProvider _freeStorageGbProvider;
  final FleetClock _clock;

  FleetHeartbeatCollector({
    FleetDeviceIdProvider? deviceIdProvider,
    FleetDeviceInfoProvider? deviceInfoProvider,
    FleetNetworkSnapshotProvider? networkSnapshotProvider,
    FleetPackageInfoProvider? packageInfoProvider,
    FleetBatteryReadingProvider? batteryReadingProvider,
    FleetFreeStorageGbProvider? freeStorageGbProvider,
    FleetClock? clock,
  })  : _deviceIdProvider =
            deviceIdProvider ?? DeviceIdService.getOrCreateDeviceId,
        _deviceInfoProvider =
            deviceInfoProvider ?? DeviceIdService.getDeviceInfo,
        _networkSnapshotProvider =
            networkSnapshotProvider ?? NetworkInfoService.getCurrentSnapshot,
        _packageInfoProvider = packageInfoProvider ?? _readPackageDetails,
        _batteryReadingProvider = batteryReadingProvider ?? _readBatteryReading,
        _freeStorageGbProvider = freeStorageGbProvider ?? _readFreeStorageGb,
        _clock = clock ?? DateTime.now;

  Future<FleetHeartbeatSnapshot> collect({
    required String labLabel,
    required String runtimeRole,
    required String fleetMode,
    required bool isRecording,
    required int uploadQueueDepth,
    String? activeSessionGuid,
  }) async {
    final additionalWarnings = <String>[];
    final deviceId = await _deviceIdProvider();
    final deviceInfo = await _safeMapProvider(
      "FleetHeartbeatCollector: failed to read device info",
      _deviceInfoProvider,
    );
    final networkSnapshot = await _safeNetworkSnapshotProvider(
      "FleetHeartbeatCollector: failed to read network snapshot",
      _networkSnapshotProvider,
      additionalWarnings,
    );
    final packageInfo = await _safePackageInfoProvider(
      "FleetHeartbeatCollector: failed to read package info",
      _packageInfoProvider,
      additionalWarnings,
    );
    final batteryReading = await _safeNullableProvider(
      "FleetHeartbeatCollector: failed to read battery",
      _batteryReadingProvider,
    );
    final freeStorageGb = await _safeNullableProvider(
      "FleetHeartbeatCollector: failed to read free storage",
      _freeStorageGbProvider,
    );

    return FleetHeartbeatSnapshot.build(
      deviceId: deviceId,
      labLabel: labLabel,
      generatedAtUtc: _clock().toUtc(),
      appVersion: packageInfo.appVersion,
      buildNumber: packageInfo.buildNumber,
      packageName: packageInfo.packageName,
      runtimeRole: runtimeRole,
      fleetMode: fleetMode,
      networkSnapshot: networkSnapshot,
      batteryLevelPercent: batteryReading?.levelPercent,
      batteryState: batteryReading?.state,
      freeStorageGb: freeStorageGb,
      isRecording: isRecording,
      activeSessionGuid: activeSessionGuid,
      uploadQueueDepth: uploadQueueDepth,
      deviceInfo: deviceInfo,
      additionalWarnings: additionalWarnings,
    );
  }

  static Future<Map<String, dynamic>> _safeMapProvider(
    String message,
    FleetDeviceInfoProvider provider,
  ) async {
    try {
      return await provider();
    } catch (error, stackTrace) {
      LogService.instance.registerError(message, error, stackTrace);
      return const {};
    }
  }

  static Future<T?> _safeNullableProvider<T>(
    String message,
    Future<T?> Function() provider,
  ) async {
    try {
      return await provider();
    } catch (error, stackTrace) {
      LogService.instance.registerError(message, error, stackTrace);
      return null;
    }
  }

  static Future<NetworkSnapshot> _safeNetworkSnapshotProvider(
    String message,
    FleetNetworkSnapshotProvider provider,
    List<String> warnings,
  ) async {
    try {
      return await provider();
    } catch (error, stackTrace) {
      LogService.instance.registerError(message, error, stackTrace);
      warnings.add("network:unavailable");
      return const NetworkSnapshot(
        isWifiActive: false,
        source: "unavailable",
        warnings: [
          "Network snapshot unavailable.",
        ],
      );
    }
  }

  static Future<FleetPackageDetails> _safePackageInfoProvider(
    String message,
    FleetPackageInfoProvider provider,
    List<String> warnings,
  ) async {
    try {
      return await provider();
    } catch (error, stackTrace) {
      LogService.instance.registerError(message, error, stackTrace);
      warnings.add("app:package-info-unavailable");
      return FleetPackageDetails.unknown;
    }
  }

  static Future<FleetPackageDetails> _readPackageDetails() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return FleetPackageDetails.fromPackageInfo(packageInfo);
  }

  static Future<FleetBatteryReading?> _readBatteryReading() async {
    final battery = Battery();
    final level = await battery.batteryLevel;
    final state = await battery.batteryState;
    return FleetBatteryReading(
      levelPercent: level,
      state: state.name,
    );
  }

  static Future<double?> _readFreeStorageGb() async {
    final freeSpaceMb = await DiskSpacePlus().getFreeDiskSpace;
    if (freeSpaceMb == null) {
      return null;
    }
    return freeSpaceMb / 1024;
  }
}
