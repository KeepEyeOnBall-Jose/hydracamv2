import "master_server.dart";
import "../services/network_info_service.dart";

Map<String, dynamic> buildConnectedClientAutomationPayload(
  List<ConnectedDeviceInfo> clients, {
  DateTime? serverStartedAt,
  String? masterSessionGuid,
}) {
  final orderedClients = sortConnectedDeviceInfos(clients);
  final summary = summarizeConnectedDeviceInfos(orderedClients);
  final connectedClients = orderedClients.where((client) => client.isConnected);
  return {
    "knownClientCount": summary.knownCount,
    "connectedClientCount": connectedClients.length,
    "disconnectedClientCount": summary.disconnectedCount,
    "connectionSummaryLabel": summary.label,
    "connectedClientIds":
        connectedClients.map((client) => client.deviceId).toList(),
    "masterServerStartedAt": serverStartedAt?.toIso8601String(),
    "connectedClients": orderedClients
        .map((client) => {
              "deviceId": client.deviceId,
              "shortDeviceId": client.shortDeviceId,
              "isConnected": client.isConnected,
              "connectionStatusLabel": client.connectionStatusLabel,
              "remoteIp": client.remoteIp,
              "networkStatus": client.networkStatus.name,
              "networkStatusLabel": client.networkStatus.label,
              "previewStatus": client.previewStatus,
              "previewStatusLabel": client.previewStatusLabel,
              "previewTransportLabel": client.previewTransportLabel,
              "reportedSessionGuid": client.reportedSessionGuid,
              "sessionStatus":
                  client.sessionStatus(masterSessionGuid: masterSessionGuid),
              "sessionStatusLabel": client.sessionStatusLabel(
                  masterSessionGuid: masterSessionGuid),
              "identifyStatus": client.identifyStatus,
              "identifyStatusLabel": client.identifyStatusLabel,
              "lastIdentifyRequestId": client.lastIdentifyRequestId,
              "lastIdentifyRequestedAt":
                  client.lastIdentifyRequestedAt?.toIso8601String(),
              "lastIdentifyAckAt": client.lastIdentifyAckAt?.toIso8601String(),
              "registeredAt": client.registeredAt.toIso8601String(),
              "lastSeen": client.lastSeen.toIso8601String(),
              "disconnectedAt": client.disconnectedAt?.toIso8601String(),
              "network": client.networkSnapshot?.toJson(),
              "setupStatus": client.setupStatus?.toJson(),
            })
        .toList(),
  };
}
