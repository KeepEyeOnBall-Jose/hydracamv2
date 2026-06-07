import "master_server.dart";
import "../services/network_info_service.dart";

Map<String, dynamic> buildConnectedClientAutomationPayload(
    List<ConnectedDeviceInfo> clients) {
  return {
    "connectedClientCount": clients.length,
    "connectedClientIds": clients.map((client) => client.deviceId).toList(),
    "connectedClients": clients
        .map((client) => {
              "deviceId": client.deviceId,
              "shortDeviceId": client.shortDeviceId,
              "remoteIp": client.remoteIp,
              "networkStatus": client.networkStatus.name,
              "networkStatusLabel": client.networkStatus.label,
              "lastSeen": client.lastSeen.toIso8601String(),
              "network": client.networkSnapshot?.toJson(),
            })
        .toList(),
  };
}
