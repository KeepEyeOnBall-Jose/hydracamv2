import "master_server.dart";
import "../services/network_info_service.dart";

Map<String, dynamic> buildConnectedClientAutomationPayload(
  List<ConnectedDeviceInfo> clients, {
  DateTime? serverStartedAt,
}) {
  return {
    "connectedClientCount": clients.length,
    "connectedClientIds": clients.map((client) => client.deviceId).toList(),
    "masterServerStartedAt": serverStartedAt?.toIso8601String(),
    "connectedClients": clients
        .map((client) => {
              "deviceId": client.deviceId,
              "shortDeviceId": client.shortDeviceId,
              "remoteIp": client.remoteIp,
              "networkStatus": client.networkStatus.name,
              "networkStatusLabel": client.networkStatus.label,
              "registeredAt": client.registeredAt.toIso8601String(),
              "lastSeen": client.lastSeen.toIso8601String(),
              "network": client.networkSnapshot?.toJson(),
            })
        .toList(),
  };
}
