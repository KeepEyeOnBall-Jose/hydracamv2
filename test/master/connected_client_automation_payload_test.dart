import "package:flutter_test/flutter_test.dart";
import "package:hydracam/master/connected_client_automation_payload.dart";
import "package:hydracam/master/master_server.dart";
import "package:hydracam/services/network_info_service.dart";

void main() {
  test("connected client automation payload exposes client readiness", () {
    final payload = buildConnectedClientAutomationPayload([
      ConnectedDeviceInfo(
        deviceId: "slave-device-a",
        remoteIp: "192.168.178.62",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 7, 11, 59, 59, 500),
        lastSeen: DateTime.utc(2026, 6, 7, 12, 0),
        networkSnapshot: const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.62",
          source: "test",
        ),
      ),
    ], serverStartedAt: DateTime.utc(2026, 6, 7, 11, 59, 59));

    expect(payload["connectedClientCount"], 1);
    expect(payload["connectedClientIds"], ["slave-device-a"]);
    expect(payload["connectedClients"], [
      {
        "deviceId": "slave-device-a",
        "shortDeviceId": "slave-de",
        "isConnected": true,
        "connectionStatusLabel": "Connected",
        "remoteIp": "192.168.178.62",
        "networkStatus": "ready",
        "networkStatusLabel": "Ready",
        "previewStatus": "unavailable",
        "previewStatusLabel": "Preview unavailable",
        "previewTransportLabel": "Preview transport not configured",
        "reportedSessionGuid": null,
        "sessionStatus": "unknown",
        "sessionStatusLabel": "Session not reported",
        "identifyStatus": "notRequested",
        "identifyStatusLabel": "Identify not requested",
        "lastIdentifyRequestId": null,
        "lastIdentifyRequestedAt": null,
        "lastIdentifyAckAt": null,
        "registeredAt": "2026-06-07T11:59:59.500Z",
        "lastSeen": "2026-06-07T12:00:00.000Z",
        "disconnectedAt": null,
        "network": {
          "isWifiActive": true,
          "ipAddress": "192.168.178.62",
          "ssid": null,
          "bssid": null,
          "gatewayIp": null,
          "subnetMask": null,
          "subnetSignature": "192.168.178.0/24",
          "source": "test",
          "warnings": [],
        },
        "setupStatus": null,
      },
    ]);
    expect(payload["masterServerStartedAt"], "2026-06-07T11:59:59.000Z");
  });

  test("connected client automation payload includes disconnected diagnostics",
      () {
    final payload = buildConnectedClientAutomationPayload([
      ConnectedDeviceInfo(
        deviceId: "live-slave",
        remoteIp: "192.168.178.62",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 7, 11, 59, 59, 500),
        lastSeen: DateTime.utc(2026, 6, 7, 12),
      ),
      ConnectedDeviceInfo(
        deviceId: "stale-slave",
        remoteIp: "192.168.178.63",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 7, 11, 58),
        lastSeen: DateTime.utc(2026, 6, 7, 12, 1),
        isConnected: false,
        disconnectedAt: DateTime.utc(2026, 6, 7, 12, 1),
      ),
    ]);

    expect(payload["connectedClientCount"], 1);
    expect(payload["connectedClientIds"], ["live-slave"]);
    expect(payload["connectedClients"], [
      containsPair("connectionStatusLabel", "Connected"),
      containsPair("connectionStatusLabel", "Disconnected"),
    ]);
    expect(
      (payload["connectedClients"] as List).last,
      containsPair("disconnectedAt", "2026-06-07T12:01:00.000Z"),
    );
  });

  test(
      "connected client automation payload summarizes and orders known clients",
      () {
    final payload = buildConnectedClientAutomationPayload([
      ConnectedDeviceInfo(
        deviceId: "stale-slave",
        remoteIp: "192.168.178.63",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 7, 11, 58),
        lastSeen: DateTime.utc(2026, 6, 7, 12, 1),
        isConnected: false,
        disconnectedAt: DateTime.utc(2026, 6, 7, 12, 1),
      ),
      ConnectedDeviceInfo(
        deviceId: "live-slave",
        remoteIp: "192.168.178.62",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 7, 11, 59, 59, 500),
        lastSeen: DateTime.utc(2026, 6, 7, 12),
      ),
    ]);

    expect(payload["knownClientCount"], 2);
    expect(payload["connectedClientCount"], 1);
    expect(payload["disconnectedClientCount"], 1);
    expect(payload["connectionSummaryLabel"], "1 connected · 1 disconnected");
    expect(payload["connectedClientIds"], ["live-slave"]);
    expect(
      (payload["connectedClients"] as List)
          .map((client) => client["deviceId"])
          .toList(),
      ["live-slave", "stale-slave"],
    );
  });

  test("connected client automation payload flags different slave session", () {
    final payload = buildConnectedClientAutomationPayload([
      ConnectedDeviceInfo(
        deviceId: "slave-device-a",
        remoteIp: "192.168.178.62",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 8, 21, 15),
        lastSeen: DateTime.utc(2026, 6, 8, 21, 15, 1),
        reportedSessionGuid: "slave-other-session",
      ),
    ], masterSessionGuid: "master-active-session");

    final client =
        (payload["connectedClients"] as List).single as Map<String, dynamic>;

    expect(client["reportedSessionGuid"], "slave-other-session");
    expect(client["sessionStatus"], "different");
    expect(client["sessionStatusLabel"], "Different session");
  });

  test("connected client automation payload exposes identify ack diagnostics",
      () {
    final payload = buildConnectedClientAutomationPayload([
      ConnectedDeviceInfo(
        deviceId: "slave-device-a",
        remoteIp: "192.168.178.62",
        networkStatus: ConnectedDeviceNetworkStatus.ready,
        registeredAt: DateTime.utc(2026, 6, 8, 21, 35),
        lastSeen: DateTime.utc(2026, 6, 8, 21, 35, 1),
        lastIdentifyRequestId: "identify-test",
        lastIdentifyRequestedAt: DateTime.utc(2026, 6, 8, 21, 35),
        lastIdentifyAckAt: DateTime.utc(2026, 6, 8, 21, 35, 1),
      ),
    ]);

    final client =
        (payload["connectedClients"] as List).single as Map<String, dynamic>;

    expect(client["identifyStatus"], "acknowledged");
    expect(client["identifyStatusLabel"], "Identify acknowledged");
    expect(client["lastIdentifyRequestId"], "identify-test");
    expect(
      client["lastIdentifyRequestedAt"],
      "2026-06-08T21:35:00.000Z",
    );
    expect(client["lastIdentifyAckAt"], "2026-06-08T21:35:01.000Z");
  });
}
