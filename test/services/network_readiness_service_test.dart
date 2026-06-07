import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/network_info_service.dart";

void main() {
  group("Network readiness", () {
    test("Wi-Fi disabled with no route blocks local control", () {
      final result = NetworkInfoService.evaluateLocalControlReadiness(
        const NetworkSnapshot(
          isWifiActive: false,
          source: "test",
        ),
      );

      expect(result.canUseLocalControl, false);
      expect(
        result.blockingReason,
        NetworkReadinessBlockingReason.wifiDisabled,
      );
    });

    test("Wi-Fi enabled but not connected blocks local control", () {
      final result = NetworkInfoService.evaluateLocalControlReadiness(
        const NetworkSnapshot(
          isWifiActive: true,
          source: "test",
        ),
      );

      expect(result.canUseLocalControl, false);
      expect(
        result.blockingReason,
        NetworkReadinessBlockingReason.noLocalIp,
      );
    });

    test("SSID unavailable with local route remains usable with warning", () {
      final result = NetworkInfoService.evaluateLocalControlReadiness(
        const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.132",
          subnetMask: "255.255.255.0",
          source: "test",
        ),
      );

      expect(result.canUseLocalControl, true);
      expect(result.blockingReason, NetworkReadinessBlockingReason.none);
      expect(result.message, contains("SSID unavailable"));
      expect(result.snapshot.effectiveSubnetSignature, "192.168.178.0/24");
    });

    test("local IPv4 can be usable for master checks without Wi-Fi radio gate",
        () {
      final result = NetworkInfoService.evaluateLocalControlReadiness(
        const NetworkSnapshot(
          isWifiActive: false,
          ipAddress: "192.168.43.1",
          subnetMask: "255.255.255.0",
          source: "test",
        ),
        requireWifi: false,
      );

      expect(result.canUseLocalControl, true);
      expect(result.blockingReason, NetworkReadinessBlockingReason.none);
      expect(result.snapshot.effectiveSubnetSignature, "192.168.43.0/24");
    });
  });

  group("Network protocol comparison", () {
    test("same BSSID, gateway, and subnet is ready", () {
      const master = NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.159",
        ssid: "FRITZ!Box 6591 Cable TZ",
        bssid: "2c:91:ab:8b:a3:07",
        gatewayIp: "192.168.178.1",
        subnetMask: "255.255.255.0",
        source: "test",
      );
      const slave = NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.132",
        ssid: "FRITZ!Box 6591 Cable TZ",
        bssid: "2c:91:ab:8b:a3:07",
        gatewayIp: "192.168.178.1",
        subnetMask: "255.255.255.0",
        source: "test",
      );

      final status = NetworkInfoService.compareDeviceNetwork(
        masterSnapshot: master,
        deviceSnapshot: slave,
        socketRemoteIp: "192.168.178.132",
      );

      expect(status, ConnectedDeviceNetworkStatus.ready);
    });

    test("different subnet is wrong network", () {
      const master = NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.159",
        subnetMask: "255.255.255.0",
        source: "test",
      );
      const slave = NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.50.10",
        subnetMask: "255.255.255.0",
        source: "test",
      );

      final status = NetworkInfoService.compareDeviceNetwork(
        masterSnapshot: master,
        deviceSnapshot: slave,
        socketRemoteIp: "192.168.50.10",
      );

      expect(status, ConnectedDeviceNetworkStatus.wrongNetwork);
    });

    test("existing clients without network payload remain unknown", () {
      const master = NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.159",
        subnetMask: "255.255.255.0",
        source: "test",
      );

      final parsedPayload = NetworkSnapshot.tryFromJson(null);
      final status = NetworkInfoService.compareDeviceNetwork(
        masterSnapshot: master,
        deviceSnapshot: parsedPayload,
        socketRemoteIp: "192.168.178.64",
      );

      expect(status, ConnectedDeviceNetworkStatus.unknown);
    });

    test("heartbeat network payload can refresh an unknown client to ready",
        () {
      const master = NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.159",
        subnetMask: "255.255.255.0",
        source: "test",
      );

      final heartbeatSnapshot = NetworkSnapshot.tryFromJson({
        "isWifiActive": true,
        "ipAddress": "192.168.178.64",
        "subnetMask": "255.255.255.0",
        "source": "heartbeat",
      });
      final status = NetworkInfoService.compareDeviceNetwork(
        masterSnapshot: master,
        deviceSnapshot: heartbeatSnapshot,
        socketRemoteIp: "192.168.178.64",
      );

      expect(status, ConnectedDeviceNetworkStatus.ready);
    });
  });

  group("IP address fallback selection", () {
    test("prefers LAN IPv4 over USB link-local IPv4", () {
      final selectedIp = NetworkInfoService.selectPreferredIpAddress([
        InternetAddress("169.254.9.236"),
        InternetAddress("192.168.178.104"),
      ]);

      expect(selectedIp, "192.168.178.104");
    });

    test("prefers route-selected LAN IPv4 over link-local Wi-Fi candidate", () {
      final selectedIp = NetworkInfoService.selectPreferredIpAddress(
        [InternetAddress("169.254.9.236")],
        routeSelectedIpAddress: "192.168.178.104",
      );

      expect(selectedIp, "192.168.178.104");
    });
  });
}
