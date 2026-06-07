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
        lastSeen: DateTime.utc(2026, 6, 7, 12, 0),
        networkSnapshot: const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.62",
          source: "test",
        ),
      ),
    ]);

    expect(payload["connectedClientCount"], 1);
    expect(payload["connectedClientIds"], ["slave-device-a"]);
    expect(payload["connectedClients"], [
      {
        "deviceId": "slave-device-a",
        "shortDeviceId": "slave-de",
        "remoteIp": "192.168.178.62",
        "networkStatus": "ready",
        "networkStatusLabel": "Ready",
        "lastSeen": "2026-06-07T12:00:00.000Z",
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
      },
    ]);
  });
}
