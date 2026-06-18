import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/fleet_heartbeat_service.dart";
import "package:hydracam/services/network_info_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("FleetHeartbeatSnapshot", () {
    test("builds ready lab-managed heartbeat payload", () {
      final snapshot = FleetHeartbeatSnapshot.build(
        deviceId: "device-abc123",
        labLabel: "HydraCam-S10e-01",
        generatedAtUtc: DateTime.utc(2026, 6, 15, 10, 30),
        appVersion: "1.4.0",
        buildNumber: "16",
        packageName: "com.amaia23.hydracam",
        runtimeRole: "slave",
        fleetMode: "lab-managed",
        networkSnapshot: const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.42",
          ssid: "HydraCamLab",
          subnetMask: "255.255.255.0",
          gatewayIp: "192.168.178.1",
          source: "test",
        ),
        batteryLevelPercent: 87,
        batteryState: "charging",
        freeStorageGb: 37.5,
        isRecording: false,
        activeSessionGuid: "session-123",
        uploadQueueDepth: 2,
        deviceInfo: const {
          "brand": "samsung",
          "model": "SM-G970F",
          "version.release": "12",
        },
      );

      final json = snapshot.toJson();

      expect(snapshot.health, FleetHeartbeatHealth.ready);
      expect(json["schemaVersion"], 1);
      expect(json["fleetMode"], "lab-managed");
      expect(json["deviceId"], "device-abc123");
      expect(json["labLabel"], "HydraCam-S10e-01");
      expect(json["generatedAtUtc"], "2026-06-15T10:30:00.000Z");
      expect(json["health"], "ready");
      expect(json["warnings"], isEmpty);
      expect(json["blockers"], isEmpty);
      expect(json["supportedCommands"], contains("start_recording"));
      expect(json["supportedCommands"], contains("upload_logs"));

      final app = json["app"] as Map<String, dynamic>;
      expect(app["version"], "1.4.0");
      expect(app["buildNumber"], "16");
      expect(app["packageName"], "com.amaia23.hydracam");

      final network = json["network"] as Map<String, dynamic>;
      expect(network["localControlReady"], isTrue);
      expect(network["subnetSignature"], "192.168.178.0/24");

      final role = json["role"] as Map<String, dynamic>;
      expect(role["current"], "slave");
      expect(role["recording"], isFalse);
      expect(role["activeSessionGuid"], "session-123");

      final upload = json["upload"] as Map<String, dynamic>;
      expect(upload["queueDepth"], 2);
    });

    test("marks heartbeat blocked when network battery and storage are unsafe",
        () {
      final snapshot = FleetHeartbeatSnapshot.build(
        deviceId: "device-blocked",
        labLabel: "HydraCam-S10e-02",
        generatedAtUtc: DateTime.utc(2026, 6, 15),
        appVersion: "1.4.0",
        buildNumber: "16",
        packageName: "com.amaia23.hydracam",
        runtimeRole: "standby",
        fleetMode: "lab-managed",
        networkSnapshot: const NetworkSnapshot(
          isWifiActive: true,
          source: "test",
        ),
        batteryLevelPercent: 8,
        batteryState: "discharging",
        freeStorageGb: 0.4,
        isRecording: false,
        uploadQueueDepth: 0,
      );

      expect(snapshot.health, FleetHeartbeatHealth.blocked);
      expect(snapshot.blockers, contains("network:no-local-ip"));
      expect(snapshot.blockers, contains("battery:critical"));
      expect(snapshot.blockers, contains("storage:critical"));

      final json = snapshot.toJson();
      expect(json["health"], "blocked");
      expect(json["blockers"], contains("network:no-local-ip"));
    });

    test("uses stable network warning codes in heartbeat payload", () {
      final snapshot = FleetHeartbeatSnapshot.build(
        deviceId: "device-warning",
        labLabel: "HydraCam-S10e-03",
        generatedAtUtc: DateTime.utc(2026, 6, 15),
        appVersion: "1.4.0",
        buildNumber: "16",
        packageName: "com.amaia23.hydracam",
        runtimeRole: "standby",
        fleetMode: "lab-managed",
        networkSnapshot: const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.43",
          source: "test",
          warnings: [
            "SSID unavailable; grant location permission and enable Location Services.",
          ],
        ),
        batteryLevelPercent: 54,
        batteryState: "discharging",
        freeStorageGb: 10,
        isRecording: false,
        uploadQueueDepth: 0,
      );

      expect(snapshot.health, FleetHeartbeatHealth.warning);
      expect(snapshot.warnings, ["network:ssid-unavailable"]);
      expect(snapshot.toJson()["warnings"], ["network:ssid-unavailable"]);
    });

    test("uses unknown warnings for absent battery and storage readings", () {
      final snapshot = FleetHeartbeatSnapshot.build(
        deviceId: "device-missing-readings",
        labLabel: "HydraCam-S10e-04",
        generatedAtUtc: DateTime.utc(2026, 6, 18, 16, 25),
        appVersion: "1.4.0",
        buildNumber: "16",
        packageName: "com.amaia23.hydracam",
        runtimeRole: "standby",
        fleetMode: "lab-managed",
        networkSnapshot: const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.44",
          source: "test",
        ),
        batteryLevelPercent: null,
        batteryState: null,
        freeStorageGb: null,
        isRecording: false,
        uploadQueueDepth: 0,
      );

      expect(snapshot.health, FleetHeartbeatHealth.warning);
      expect(snapshot.warnings, contains("battery:unknown"));
      expect(snapshot.warnings, contains("storage:unknown"));
      expect(snapshot.warnings, isNot(contains("battery:unavailable")));
      expect(snapshot.warnings, isNot(contains("storage:unavailable")));
    });
  });

  group("FleetHeartbeatCollector", () {
    test("uses injected providers to collect one heartbeat", () async {
      final collector = FleetHeartbeatCollector(
        deviceIdProvider: () async => "device-from-provider",
        deviceInfoProvider: () async => const {
          "model": "SM-G970F",
          "version.sdkInt": 31,
        },
        networkSnapshotProvider: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.50.25",
          ssid: "HydraCamLab",
          subnetMask: "255.255.255.0",
          source: "test",
        ),
        packageInfoProvider: () async => const FleetPackageDetails(
          appVersion: "1.4.0",
          buildNumber: "16",
          packageName: "com.amaia23.hydracam",
        ),
        batteryReadingProvider: () async => const FleetBatteryReading(
          levelPercent: 76,
          state: "charging",
        ),
        freeStorageGbProvider: () async => 22.25,
        clock: () => DateTime.utc(2026, 6, 15, 12),
      );

      final snapshot = await collector.collect(
        labLabel: "HydraCam-S10e-01",
        runtimeRole: "standby",
        fleetMode: "lab-managed",
        isRecording: false,
        uploadQueueDepth: 0,
      );

      expect(snapshot.deviceId, "device-from-provider");
      expect(snapshot.labLabel, "HydraCam-S10e-01");
      expect(snapshot.generatedAtUtc, DateTime.utc(2026, 6, 15, 12));
      expect(snapshot.health, FleetHeartbeatHealth.ready);
      expect(snapshot.deviceInfo["model"], "SM-G970F");
    });

    test("returns degraded heartbeat when network and package providers fail",
        () async {
      final collector = FleetHeartbeatCollector(
        deviceIdProvider: () async => "degraded-device",
        deviceInfoProvider: () async => const {
          "model": "SM-G970F",
        },
        networkSnapshotProvider: () async {
          throw StateError("network plugin unavailable");
        },
        packageInfoProvider: () async {
          throw StateError("package plugin unavailable");
        },
        batteryReadingProvider: () async => const FleetBatteryReading(
          levelPercent: 76,
          state: "charging",
        ),
        freeStorageGbProvider: () async => 22.25,
        clock: () => DateTime.utc(2026, 6, 15, 12),
      );

      final snapshot = await collector.collect(
        labLabel: "HydraCam-S10e-01",
        runtimeRole: "standby",
        fleetMode: "lab-managed",
        isRecording: false,
        uploadQueueDepth: 0,
      );

      expect(snapshot.deviceId, "degraded-device");
      expect(snapshot.appVersion, "unknown");
      expect(snapshot.buildNumber, "unknown");
      expect(snapshot.packageName, "unknown");
      expect(snapshot.localControlReady, isFalse);
      expect(snapshot.health, FleetHeartbeatHealth.blocked);
      expect(snapshot.blockers, contains("network:wifi-disabled"));
      expect(snapshot.warnings, contains("network:unavailable"));
      expect(snapshot.warnings, contains("app:package-info-unavailable"));
    });

    test(
        "distinguishes failed battery and storage providers from unknown readings",
        () async {
      final collector = FleetHeartbeatCollector(
        deviceIdProvider: () async => "provider-failure-device",
        deviceInfoProvider: () async => const {
          "model": "SM-G970F",
        },
        networkSnapshotProvider: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.50.25",
          ssid: "HydraCamLab",
          subnetMask: "255.255.255.0",
          source: "test",
        ),
        packageInfoProvider: () async => const FleetPackageDetails(
          appVersion: "1.4.0",
          buildNumber: "16",
          packageName: "com.amaia23.hydracam",
        ),
        batteryReadingProvider: () async {
          throw StateError("battery plugin unavailable");
        },
        freeStorageGbProvider: () async {
          throw StateError("storage plugin unavailable");
        },
        clock: () => DateTime.utc(2026, 6, 18, 16, 25),
      );

      final snapshot = await collector.collect(
        labLabel: "HydraCam-S10e-01",
        runtimeRole: "standby",
        fleetMode: "lab-managed",
        isRecording: false,
        uploadQueueDepth: 0,
      );

      expect(snapshot.health, FleetHeartbeatHealth.warning);
      expect(snapshot.warnings, contains("battery:unavailable"));
      expect(snapshot.warnings, contains("storage:unavailable"));
      expect(snapshot.warnings, isNot(contains("battery:unknown")));
      expect(snapshot.warnings, isNot(contains("storage:unknown")));
    });
  });
}
