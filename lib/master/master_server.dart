import "dart:async";
import "dart:convert"; // Import for jsonDecode
import "dart:io";
import "package:flutter/foundation.dart";
import "../globals.dart";
// import "package:gallery_saver/gallery_saver.dart";  // Temporarily disabled - incompatible plugin
import "../models/capture_context_metadata.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../models/sync_metadata.dart";
import "../services/camera_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_media_storage.dart";
import "../services/session_manager.dart";

/// MasterServer - Handles the master device's WebSocket server.
/// This class manages communication with slave devices, tracks active connections,
/// receives captured media, and manages sessions via the `SessionManager`.
///
/// ### Responsibilities:
/// - Starts and stops a WebSocket server for handling slave connections.
/// - Manages client registrations and disconnections.
/// - Receives media (photos and videos) from slave devices and adds them to the active session.
/// - Sends commands to all connected slaves or specific devices.
/// - Tracks the heartbeat of connected clients to identify inactive ones.

class ConnectedDeviceInfo {
  final String deviceId;
  final String? remoteIp;
  final NetworkSnapshot? networkSnapshot;
  final ConnectedDeviceNetworkStatus networkStatus;
  final ConnectedDeviceSetupStatus? setupStatus;
  final DateTime lastSeen;
  final DateTime registeredAt;
  final bool isConnected;
  final DateTime? disconnectedAt;
  final String? reportedSessionGuid;
  final String? appVersion;
  final String? appBuildNumber;
  final String? hardwareLabel;
  final Map<String, int>? sessionMedia;
  final String? lastIdentifyRequestId;
  final DateTime? lastIdentifyRequestedAt;
  final DateTime? lastIdentifyAckAt;

  static const Object _unchanged = Object();

  const ConnectedDeviceInfo({
    required this.deviceId,
    required this.networkStatus,
    required this.lastSeen,
    required this.registeredAt,
    this.isConnected = true,
    this.disconnectedAt,
    this.remoteIp,
    this.networkSnapshot,
    this.setupStatus,
    this.reportedSessionGuid,
    this.appVersion,
    this.appBuildNumber,
    this.hardwareLabel,
    this.sessionMedia,
    this.lastIdentifyRequestId,
    this.lastIdentifyRequestedAt,
    this.lastIdentifyAckAt,
  });

  String get shortDeviceId {
    if (deviceId.length <= 8) {
      return deviceId;
    }
    return deviceId.substring(0, 8);
  }

  String get connectionStatusLabel {
    return isConnected ? "Connected" : "Disconnected";
  }

  String get networkStatusLabel {
    if (!isConnected) {
      return "Last reported: ${networkStatus.label}";
    }
    return networkStatus.label;
  }

  String get previewStatus {
    if (!isConnected) {
      return "unavailableDisconnected";
    }
    return "unavailable";
  }

  String get previewStatusLabel {
    if (!isConnected) {
      return "Preview unavailable: disconnected";
    }
    return "Preview unavailable";
  }

  String get previewTransportLabel {
    if (!isConnected) {
      return "Slave disconnected";
    }
    return "Preview transport not configured";
  }

  String get setupStatusLabel {
    final status = setupStatus;
    if (status == null) {
      return "Setup: not reported";
    }
    final prefix = isConnected ? "Setup" : "Last reported setup";
    final levelLabel = status.isLevel ? "Level" : "Tilted";
    return "$prefix: ${status.cameraPerspectiveLabel} | $levelLabel";
  }

  String get identifyStatus {
    final ackAt = lastIdentifyAckAt;
    final requestedAt = lastIdentifyRequestedAt;
    if (ackAt != null &&
        (requestedAt == null || !ackAt.isBefore(requestedAt))) {
      return "acknowledged";
    }
    if (!isConnected && requestedAt != null) {
      return "unavailable";
    }
    if (requestedAt != null) {
      return "requested";
    }
    return "notRequested";
  }

  String get identifyStatusLabel {
    final status = identifyStatus;
    final label = switch (status) {
      "acknowledged" => "Identify acknowledged",
      "unavailable" => "Identify unavailable: disconnected",
      "requested" => "Identify requested",
      _ => "Identify not requested",
    };

    if (!isConnected && status == "acknowledged") {
      return "Last reported: $label";
    }

    return label;
  }

  String sessionStatus({String? masterSessionGuid}) {
    final slaveSessionGuid = reportedSessionGuid;
    if (slaveSessionGuid == null || slaveSessionGuid.isEmpty) {
      return "unknown";
    }
    if (masterSessionGuid == null || masterSessionGuid.isEmpty) {
      return "masterUnavailable";
    }
    return slaveSessionGuid == masterSessionGuid ? "matching" : "different";
  }

  String sessionStatusLabel({String? masterSessionGuid}) {
    final status = sessionStatus(masterSessionGuid: masterSessionGuid);
    final label = switch (status) {
      "matching" => "Same session",
      "different" => "Different session",
      "masterUnavailable" => "Master session unavailable",
      _ => "Session not reported",
    };

    if (!isConnected && (status == "matching" || status == "different")) {
      return "Last reported: $label";
    }

    return label;
  }

  ConnectedDeviceInfo copyWith({
    String? remoteIp,
    NetworkSnapshot? networkSnapshot,
    ConnectedDeviceNetworkStatus? networkStatus,
    ConnectedDeviceSetupStatus? setupStatus,
    DateTime? lastSeen,
    DateTime? registeredAt,
    bool? isConnected,
    Object? disconnectedAt = _unchanged,
    String? reportedSessionGuid,
    String? appVersion,
    String? appBuildNumber,
    String? hardwareLabel,
    Map<String, int>? sessionMedia,
    String? lastIdentifyRequestId,
    DateTime? lastIdentifyRequestedAt,
    DateTime? lastIdentifyAckAt,
  }) {
    return ConnectedDeviceInfo(
      deviceId: deviceId,
      remoteIp: remoteIp ?? this.remoteIp,
      networkSnapshot: networkSnapshot ?? this.networkSnapshot,
      networkStatus: networkStatus ?? this.networkStatus,
      setupStatus: setupStatus ?? this.setupStatus,
      lastSeen: lastSeen ?? this.lastSeen,
      registeredAt: registeredAt ?? this.registeredAt,
      isConnected: isConnected ?? this.isConnected,
      disconnectedAt: disconnectedAt == _unchanged
          ? this.disconnectedAt
          : disconnectedAt as DateTime?,
      reportedSessionGuid: reportedSessionGuid ?? this.reportedSessionGuid,
      appVersion: appVersion ?? this.appVersion,
      appBuildNumber: appBuildNumber ?? this.appBuildNumber,
      hardwareLabel: hardwareLabel ?? this.hardwareLabel,
      sessionMedia: sessionMedia ?? this.sessionMedia,
      lastIdentifyRequestId:
          lastIdentifyRequestId ?? this.lastIdentifyRequestId,
      lastIdentifyRequestedAt:
          lastIdentifyRequestedAt ?? this.lastIdentifyRequestedAt,
      lastIdentifyAckAt: lastIdentifyAckAt ?? this.lastIdentifyAckAt,
    );
  }
}

class ConnectedDeviceListSummary {
  final int knownCount;
  final int connectedCount;
  final int disconnectedCount;

  const ConnectedDeviceListSummary({
    required this.knownCount,
    required this.connectedCount,
    required this.disconnectedCount,
  });

  String get label {
    if (knownCount == 0) {
      return "No known devices";
    }
    return "$connectedCount connected · $disconnectedCount disconnected";
  }
}

ConnectedDeviceListSummary summarizeConnectedDeviceInfos(
  Iterable<ConnectedDeviceInfo> devices,
) {
  final deviceList = devices.toList();
  final connectedCount =
      deviceList.where((device) => device.isConnected).length;
  return ConnectedDeviceListSummary(
    knownCount: deviceList.length,
    connectedCount: connectedCount,
    disconnectedCount: deviceList.length - connectedCount,
  );
}

List<ConnectedDeviceInfo> sortConnectedDeviceInfos(
  Iterable<ConnectedDeviceInfo> devices,
) {
  return devices.toList()
    ..sort((a, b) {
      if (a.isConnected != b.isConnected) {
        return a.isConnected ? -1 : 1;
      }
      return a.deviceId.compareTo(b.deviceId);
    });
}

Map<String, dynamic> masterSessionStatusResponsePayload(String? sessionGuid) {
  if (sessionGuid == null || sessionGuid.isEmpty) {
    return {"command": "noSession"};
  }
  return {
    "command": "sessionStatus",
    "sessionGuid": sessionGuid,
  };
}

String encodeMasterSessionStatusResponse(String? sessionGuid) {
  return jsonEncode(masterSessionStatusResponsePayload(sessionGuid));
}

class ConnectedDeviceSetupStatus {
  const ConnectedDeviceSetupStatus({
    required this.cameraPerspectiveId,
    required this.cameraPerspectiveLabel,
    required this.isLevel,
    required this.sensorAvailable,
    this.rollDegrees,
    this.pitchDegrees,
  });

  final String cameraPerspectiveId;
  final String cameraPerspectiveLabel;
  final bool isLevel;
  final bool sensorAvailable;
  final double? rollDegrees;
  final double? pitchDegrees;

  static ConnectedDeviceSetupStatus? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final map = value.map((key, value) => MapEntry(key.toString(), value));
    final id = map["cameraPerspectiveId"]?.toString();
    final label = map["cameraPerspectiveLabel"]?.toString();
    if (id == null || id.isEmpty || label == null || label.isEmpty) {
      return null;
    }
    return ConnectedDeviceSetupStatus(
      cameraPerspectiveId: id,
      cameraPerspectiveLabel: label,
      isLevel: map["isLevel"] == true,
      sensorAvailable: map["sensorAvailable"] == true,
      rollDegrees: _toDouble(map["rollDegrees"]),
      pitchDegrees: _toDouble(map["pitchDegrees"]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "cameraPerspectiveId": cameraPerspectiveId,
      "cameraPerspectiveLabel": cameraPerspectiveLabel,
      "isLevel": isLevel,
      "sensorAvailable": sensorAvailable,
      if (rollDegrees != null) "rollDegrees": rollDegrees,
      if (pitchDegrees != null) "pitchDegrees": pitchDegrees,
    };
  }

  static double? _toDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

Map<String, int>? _intMapValue(Object? value) {
  final map = _mapValue(value);
  if (map == null) {
    return null;
  }
  return map.map((key, value) {
    final parsedValue =
        value is int ? value : int.tryParse(value?.toString() ?? "");
    return MapEntry(key, parsedValue ?? 0);
  });
}

String? _stringValue(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

class MasterNetworkSnapshotCache {
  MasterNetworkSnapshotCache({
    required this.loadSnapshot,
    this.ttl = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<NetworkSnapshot> Function() loadSnapshot;
  final Duration ttl;
  final DateTime Function() _now;

  NetworkSnapshot? _snapshot;
  DateTime? _loadedAt;

  Future<NetworkSnapshot> current() async {
    final cached = _snapshot;
    final loadedAt = _loadedAt;
    final currentTime = _now();
    if (cached != null &&
        loadedAt != null &&
        currentTime.difference(loadedAt) <= ttl) {
      return cached;
    }

    final fresh = await loadSnapshot();
    _snapshot = fresh;
    _loadedAt = currentTime;
    return fresh;
  }
}

typedef MasterSocketBinder = Future<HttpServer> Function({
  Object address,
  int port,
});

class MasterServer {
  HttpServer? _server;
  final Map<String, WebSocket> _clients =
      {}; // Map to store clients with deviceId as key
  final Map<String, DateTime> _lastHeartbeat =
      {}; // Track last heartbeat per client
  final Map<String, ConnectedDeviceInfo> _clientInfo = {};
  DateTime? _serverStartedAt;
  bool _stopRequested = false;
  NetworkSnapshot? _masterNetworkSnapshot;
  late final MasterNetworkSnapshotCache _masterNetworkSnapshotCache;
  late final MasterSocketBinder _bindMasterSocket;
  Timer? _heartbeatCheckTimer; // Timer for checking inactive clients
  Function(int)? onClientCountChange;
  Function(dynamic)? onMediaReceived; // Callback for media reception
  Function(String, int)?
      onClientRemoved; // Callback for managing slaves disconnecting

  /// Camera service is used for capturing media directly on the master device
  final CameraService cameraService;
  late final SessionMediaStorage _sessionMediaStorage;
  final DateTime Function() _now;

  /// Optional constructor for MasterServer. Probably will be deleted
  ///
  /// - `cameraService`: The service to handle camera-related operations.
  MasterServer(
    this.cameraService, {
    MasterNetworkSnapshotCache? masterNetworkSnapshotCache,
    SessionMediaStorage? sessionMediaStorage,
    MasterSocketBinder? bindMasterSocket,
    @visibleForTesting DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _sessionMediaStorage = sessionMediaStorage ?? SessionMediaStorage();
    _bindMasterSocket = bindMasterSocket ?? MasterServer.bindMasterSocket;
    _masterNetworkSnapshotCache = masterNetworkSnapshotCache ??
        MasterNetworkSnapshotCache(
          loadSnapshot: NetworkInfoService.getCurrentSnapshot,
        );
  }

  /// Starts the WebSocket server on the master device and initializes the heartbeat check mechanism.
  /// This method binds to a specific port and listens for incoming connections.
  static Future<HttpServer> bindMasterSocket({
    Object address = "0.0.0.0",
    int port = 4040,
  }) {
    return HttpServer.bind(address, port, shared: true);
  }

  Future<void> startServer() async {
    _stopRequested = false;
    try {
      final boundServer = await _bindMasterSocket();
      if (_stopRequested) {
        await boundServer.close(force: true);
        LogService.instance.registerLog(
            "WebSocket Server startup cancelled because stop was requested.");
        return;
      }

      _server = boundServer;
      _serverStartedAt = DateTime.now();
      LogService.instance
          .registerLog("WebSocket Server successfully started on port 4040");

      // Init check to verify inactive clients
      _startHeartbeatCheck();

      _server!.listen((HttpRequest request) async {
        if (request.uri.path == "/ws") {
          final remoteIp = request.connectionInfo?.remoteAddress.address;
          final socket = await WebSocketTransformer.upgrade(request);
          LogService.instance.registerLog("New WebSocket client connected.");

          String? deviceId;

          socket.listen((data) async {
            deviceId = await _handleIncomingMessage(
              data,
              socket: socket,
              remoteIp: remoteIp,
              currentDeviceId: deviceId,
            );
          }, onDone: () {
            // Manage client disconnection
            if (deviceId != null) {
              _removeClientIfCurrent(
                deviceId: deviceId!,
                socket: socket,
                logMessage:
                    "Client $deviceId disconnected. Total clients: {count}",
              );
            }
          }, onError: (error) {
            // Manage error in connection
            if (deviceId != null) {
              _removeClientIfCurrent(
                deviceId: deviceId!,
                socket: socket,
                logMessage:
                    "Error with client $deviceId: $error. Removed from clients.",
              );
            }
          });
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      }, onError: (Object error) {
        LogService.instance
            .registerLog("WebSocket Server request error: $error");
      });
    } catch (e) {
      LogService.instance.registerLog("Failed to start WebSocket Server: $e");
    }
  }

  @visibleForTesting
  Future<void> handleIncomingMessageForTest(
    Object data, {
    required WebSocket socket,
    String? remoteIp,
  }) async {
    await _handleIncomingMessage(
      data,
      socket: socket,
      remoteIp: remoteIp,
      currentDeviceId: null,
    );
  }

  Future<String?> _handleIncomingMessage(
    Object data, {
    required WebSocket socket,
    required String? remoteIp,
    required String? currentDeviceId,
  }) async {
    // Capture the master receive time as early as possible so the round-trip
    // estimate is not polluted by decode/dispatch latency.
    final t1 = _now().toUtc();
    var deviceId = currentDeviceId;
    try {
      final decodedData = jsonDecode(data as String);
      LogService.instance.registerLog("Data received from slave: $decodedData");

      if (decodedData is! Map<String, dynamic>) {
        LogService.instance
            .registerLog("Unexpected data format received: $data");
        return deviceId;
      }

      final String? messageType = decodedData["type"]?.toString();
      final messageDeviceId = (decodedData["deviceId"] ?? "Unknown").toString();
      deviceId = messageDeviceId;

      if (messageType == "deviceId") {
        await _handleDeviceRegistrationMessage(
          decodedData,
          socket: socket,
          remoteIp: remoteIp,
          deviceId: messageDeviceId,
        );
      } else if (messageType == "photo" || messageType == "video") {
        await _handleMediaMessage(
          decodedData,
          messageType: messageType == "photo" ? "photo" : "video",
          deviceId: messageDeviceId,
        );
      } else if (messageType == "heartbeat") {
        await _handleHeartbeatMessage(
          decodedData,
          socket: socket,
          remoteIp: remoteIp,
          deviceId: messageDeviceId,
        );
      } else if (messageType == "identifyAck") {
        await _handleIdentifyAckMessage(
          decodedData,
          socket: socket,
          remoteIp: remoteIp,
          deviceId: messageDeviceId,
        );
      } else if (messageType == "getSessionStatus") {
        LogService.instance
            .registerLog("Received getSessionStatus from $deviceId");
        _sendSessionStatusResponse(socket, deviceId);
      } else if (messageType == "timeSyncRequest") {
        _handleTimeSyncRequest(decodedData, socket: socket, t1: t1);
      } else if (messageType == "forcedStop") {
        _handleForcedStopMessage(decodedData);
      }
    } catch (e) {
      LogService.instance.registerLog("Error decoding data: $e");
    }
    return deviceId;
  }

  Future<void> _handleDeviceRegistrationMessage(
    Map<String, dynamic> decodedData, {
    required WebSocket socket,
    required String? remoteIp,
    required String deviceId,
  }) async {
    await _registerOrUpdateClient(
      deviceId: deviceId,
      socket: socket,
      remoteIp: remoteIp,
      networkSnapshot: NetworkSnapshot.tryFromJson(decodedData["network"]),
      setupStatus:
          ConnectedDeviceSetupStatus.tryFromJson(decodedData["setupStatus"]),
      reportedSessionGuid: decodedData["sessionGuid"] as String?,
      appVersion: _stringValue(decodedData["appVersion"]),
      appBuildNumber: _stringValue(decodedData["appBuildNumber"]),
      hardwareLabel: _stringValue(decodedData["hardware"]),
      sessionMedia: _intMapValue(decodedData["sessionMedia"]),
    );
    LogService.instance
        .registerLog("Registered new slave with deviceId: $deviceId");

    _sendSessionStatusResponse(socket, deviceId);
  }

  Future<void> _handleMediaMessage(
    Map<String, dynamic> decodedData, {
    required String messageType,
    required String deviceId,
  }) async {
    if (_hasInboundMediaSessionMismatch(deviceId)) {
      LogService.instance.registerLog(
          "Ignored $messageType from slave $deviceId due to session mismatch.");
      return;
    }

    final Uint8List binaryData =
        Uint8List.fromList(List<int>.from(decodedData["data"]));
    final String filePath =
        await _saveMediaLocally(binaryData, messageType == "photo");
    final DateTime receivedDate = DateTime.now();

    if (messageType == "photo") {
      final DateTime captureDate = DateTime.parse(decodedData["captureDate"]);
      final receivedPhoto = CapturedPhoto(
        photoData: null,
        photoPath: filePath,
        captureDate: captureDate,
        receivedDate: receivedDate,
        slaveDeviceId: deviceId,
        captureContext: MediaCaptureContext.fromJson(
          _mapValue(decodedData["captureContext"]),
        ),
        syncMetadata: SyncMetadata.fromJson(decodedData["syncMetadata"]),
      );
      await SessionManager.instance.addPhoto(receivedPhoto);

      onMediaReceived?.call(receivedPhoto);
      LogService.instance.registerLog(
          "Photo from slave device ($deviceId) received and stored at: $filePath");
      return;
    }

    final DateTime startRecordingDate =
        DateTime.parse(decodedData["startRecordingDate"]);
    final DateTime endRecordingDate =
        DateTime.parse(decodedData["endRecordingDate"]);
    final receivedVideo = CapturedVideo(
      videoData: null,
      videoPath: filePath,
      slaveDeviceId: deviceId,
      startRecordingDate: startRecordingDate,
      endRecordingDate: endRecordingDate,
      receivedDate: receivedDate,
      captureContext: MediaCaptureContext.fromJson(
        _mapValue(decodedData["captureContext"]),
      ),
      syncMetadata: SyncMetadata.fromJson(decodedData["syncMetadata"]),
    );
    await SessionManager.instance.addVideo(receivedVideo);
    onMediaReceived?.call(receivedVideo);
    LogService.instance.registerLog(
        "Video from slave device ($deviceId) received and stored at: $filePath");
  }

  bool _hasInboundMediaSessionMismatch(String deviceId) {
    final info = _clientInfo[deviceId];
    final sessionStatus = info?.sessionStatus(
      masterSessionGuid: SessionManager.instance.sessionGuid,
    );
    return sessionStatus == "different";
  }

  Future<void> _handleHeartbeatMessage(
    Map<String, dynamic> decodedData, {
    required WebSocket socket,
    required String? remoteIp,
    required String deviceId,
  }) async {
    _lastHeartbeat[deviceId] = DateTime.now();
    await _registerOrUpdateClient(
      deviceId: deviceId,
      socket: socket,
      remoteIp: remoteIp,
      networkSnapshot: NetworkSnapshot.tryFromJson(decodedData["network"]),
      setupStatus:
          ConnectedDeviceSetupStatus.tryFromJson(decodedData["setupStatus"]),
      reportedSessionGuid: decodedData["sessionGuid"] as String?,
      appVersion: _stringValue(decodedData["appVersion"]),
      appBuildNumber: _stringValue(decodedData["appBuildNumber"]),
      hardwareLabel: _stringValue(decodedData["hardware"]),
      sessionMedia: _intMapValue(decodedData["sessionMedia"]),
    );
    LogService.instance.registerLog("Received heartbeat from $deviceId");
  }

  Future<void> _handleIdentifyAckMessage(
    Map<String, dynamic> decodedData, {
    required WebSocket socket,
    required String? remoteIp,
    required String deviceId,
  }) async {
    final acknowledgedAt = DateTime.tryParse(
          decodedData["timestamp"]?.toString() ?? "",
        ) ??
        DateTime.now();
    await _registerOrUpdateClient(
      deviceId: deviceId,
      socket: socket,
      remoteIp: remoteIp,
      networkSnapshot: NetworkSnapshot.tryFromJson(decodedData["network"]),
      setupStatus:
          ConnectedDeviceSetupStatus.tryFromJson(decodedData["setupStatus"]),
      reportedSessionGuid: decodedData["sessionGuid"] as String?,
      appVersion: _stringValue(decodedData["appVersion"]),
      appBuildNumber: _stringValue(decodedData["appBuildNumber"]),
      hardwareLabel: _stringValue(decodedData["hardware"]),
      sessionMedia: _intMapValue(decodedData["sessionMedia"]),
    );
    _recordIdentifyAck(
      deviceId: deviceId,
      requestId: decodedData["requestId"]?.toString(),
      acknowledgedAt: acknowledgedAt,
    );
    LogService.instance
        .registerLog("Received identify acknowledgement from $deviceId");
  }

  void _handleForcedStopMessage(Map<String, dynamic> decodedData) {
    final deviceId = decodedData["deviceId"];
    final reason = decodedData["reason"];
    LogService.instance
        .registerLog("Slave $deviceId forcibly stopped. Reason: $reason");
    LogService.instance
        .registerLog("Slave $deviceId forcibly stopped: $reason");
  }

  void _sendSessionStatusResponse(WebSocket socket, String? deviceId) {
    final sessionGuid = SessionManager.instance.isSessionActive
        ? SessionManager.instance.sessionGuid
        : null;
    final message = encodeMasterSessionStatusResponse(sessionGuid);
    socket.add(message);

    if (sessionGuid == null || sessionGuid.isEmpty) {
      LogService.instance.registerLog("Sent noSession to $deviceId");
      return;
    }

    LogService.instance
        .registerLog("Sent sessionStatus to $deviceId: $message");
  }

  /// Replies to a slave's clock-sync probe with the master's receive ([t1]) and
  /// send ([t2]) timestamps, echoing the request id and the slave's send time so
  /// the slave can compute offset and round-trip. The master clock is the shared
  /// reference, so no state is kept here.
  void _handleTimeSyncRequest(
    Map<String, dynamic> decodedData, {
    required WebSocket socket,
    required DateTime t1,
  }) {
    final response = jsonEncode({
      "type": "timeSyncResponse",
      "id": decodedData["id"],
      "t0": decodedData["t0"],
      "t1": t1.toIso8601String(),
      "t2": _now().toUtc().toIso8601String(),
    });
    socket.add(response);
  }

  Future<void> _registerOrUpdateClient({
    required String deviceId,
    required WebSocket socket,
    required String? remoteIp,
    required NetworkSnapshot? networkSnapshot,
    required ConnectedDeviceSetupStatus? setupStatus,
    required String? reportedSessionGuid,
    required String? appVersion,
    required String? appBuildNumber,
    required String? hardwareLabel,
    required Map<String, int>? sessionMedia,
  }) {
    final previousInfo = _clientInfo[deviceId];
    final effectiveSnapshot = networkSnapshot ?? previousInfo?.networkSnapshot;
    final effectiveSetupStatus = setupStatus ?? previousInfo?.setupStatus;
    final effectiveAppVersion = appVersion ?? previousInfo?.appVersion;
    final effectiveAppBuildNumber =
        appBuildNumber ?? previousInfo?.appBuildNumber;
    final effectiveHardwareLabel = hardwareLabel ?? previousInfo?.hardwareLabel;
    final hasReportedSession = reportedSessionGuid?.trim().isNotEmpty ?? false;
    final effectiveSessionMedia =
        hasReportedSession ? sessionMedia ?? previousInfo?.sessionMedia : null;
    final now = DateTime.now();

    _clients[deviceId] = socket;
    _lastHeartbeat[deviceId] = now;
    _clientInfo[deviceId] = ConnectedDeviceInfo(
      deviceId: deviceId,
      remoteIp: remoteIp ?? previousInfo?.remoteIp,
      networkSnapshot: effectiveSnapshot,
      networkStatus:
          previousInfo?.networkStatus ?? ConnectedDeviceNetworkStatus.unknown,
      setupStatus: effectiveSetupStatus,
      reportedSessionGuid: reportedSessionGuid,
      appVersion: effectiveAppVersion,
      appBuildNumber: effectiveAppBuildNumber,
      hardwareLabel: effectiveHardwareLabel,
      sessionMedia: effectiveSessionMedia,
      lastIdentifyRequestId: previousInfo?.lastIdentifyRequestId,
      lastIdentifyRequestedAt: previousInfo?.lastIdentifyRequestedAt,
      lastIdentifyAckAt: previousInfo?.lastIdentifyAckAt,
      lastSeen: now,
      registeredAt: previousInfo?.registeredAt ?? now,
    );

    _notifyClientCount();

    unawaited(_refreshRegisteredClientNetworkStatus(
      deviceId: deviceId,
      socket: socket,
      remoteIp: remoteIp,
      networkSnapshot: effectiveSnapshot,
    ));
    return Future<void>.value();
  }

  Future<void> _refreshRegisteredClientNetworkStatus({
    required String deviceId,
    required WebSocket socket,
    required String? remoteIp,
    required NetworkSnapshot? networkSnapshot,
  }) async {
    final masterSnapshot = await _getMasterNetworkSnapshot();
    if (!identical(_clients[deviceId], socket)) {
      return;
    }

    final previousInfo = _clientInfo[deviceId];
    final effectiveSnapshot = networkSnapshot ?? previousInfo?.networkSnapshot;
    final now = DateTime.now();
    final networkStatus = NetworkInfoService.compareDeviceNetwork(
      masterSnapshot: masterSnapshot,
      deviceSnapshot: effectiveSnapshot,
      socketRemoteIp: remoteIp,
    );

    _clientInfo[deviceId] = ConnectedDeviceInfo(
      deviceId: deviceId,
      remoteIp: remoteIp ?? previousInfo?.remoteIp,
      networkSnapshot: effectiveSnapshot,
      networkStatus: networkStatus,
      setupStatus: previousInfo?.setupStatus,
      reportedSessionGuid: previousInfo?.reportedSessionGuid,
      appVersion: previousInfo?.appVersion,
      appBuildNumber: previousInfo?.appBuildNumber,
      hardwareLabel: previousInfo?.hardwareLabel,
      sessionMedia: previousInfo?.sessionMedia,
      lastIdentifyRequestId: previousInfo?.lastIdentifyRequestId,
      lastIdentifyRequestedAt: previousInfo?.lastIdentifyRequestedAt,
      lastIdentifyAckAt: previousInfo?.lastIdentifyAckAt,
      lastSeen: now,
      registeredAt: previousInfo?.registeredAt ?? now,
    );

    if (networkStatus == ConnectedDeviceNetworkStatus.wrongNetwork) {
      socket.add(jsonEncode({
        "command": "networkMismatch",
        "message": "This slave is not on the same local network as the master.",
        "masterNetwork": masterSnapshot.toJson(),
      }));
      LogService.instance.registerLog(
          "Slave $deviceId appears to be on the wrong network. remoteIp=$remoteIp "
          "slaveSubnet=${effectiveSnapshot?.effectiveSubnetSignature} "
          "masterSubnet=${masterSnapshot.effectiveSubnetSignature}");
    }

    _notifyClientCount();
  }

  void _removeClientIfCurrent({
    required String deviceId,
    required WebSocket socket,
    required String logMessage,
  }) {
    if (!identical(_clients[deviceId], socket)) {
      return;
    }

    _clients.remove(deviceId);
    _lastHeartbeat.remove(deviceId);
    _markClientDisconnected(deviceId);
    _notifyClientCount();
    LogService.instance
        .registerLog(logMessage.replaceAll("{count}", "${_clients.length}"));
  }

  void _markClientDisconnected(String deviceId) {
    final previousInfo = _clientInfo[deviceId];
    if (previousInfo == null) {
      return;
    }
    final now = DateTime.now();
    _clientInfo[deviceId] = previousInfo.copyWith(
      isConnected: false,
      disconnectedAt: now,
      lastSeen: now,
    );
  }

  void _recordIdentifyAck({
    required String deviceId,
    required String? requestId,
    required DateTime acknowledgedAt,
  }) {
    final previousInfo = _clientInfo[deviceId];
    if (previousInfo == null) {
      return;
    }
    _lastHeartbeat[deviceId] = acknowledgedAt;
    _clientInfo[deviceId] = previousInfo.copyWith(
      lastSeen: acknowledgedAt,
      isConnected: true,
      disconnectedAt: null,
      lastIdentifyRequestId: requestId ?? previousInfo.lastIdentifyRequestId,
      lastIdentifyAckAt: acknowledgedAt,
    );
    _notifyClientCount();
  }

  @visibleForTesting
  Future<void> registerOrUpdateClientForTest({
    required String deviceId,
    required WebSocket socket,
    required String? remoteIp,
    required NetworkSnapshot? networkSnapshot,
    ConnectedDeviceSetupStatus? setupStatus,
    String? reportedSessionGuid,
    String? appVersion,
    String? appBuildNumber,
    String? hardwareLabel,
    Map<String, int>? sessionMedia,
  }) {
    return _registerOrUpdateClient(
      deviceId: deviceId,
      socket: socket,
      remoteIp: remoteIp,
      networkSnapshot: networkSnapshot,
      setupStatus: setupStatus,
      reportedSessionGuid: reportedSessionGuid,
      appVersion: appVersion,
      appBuildNumber: appBuildNumber,
      hardwareLabel: hardwareLabel,
      sessionMedia: sessionMedia,
    );
  }

  @visibleForTesting
  void removeClientIfCurrentForTest({
    required String deviceId,
    required WebSocket socket,
  }) {
    _removeClientIfCurrent(
      deviceId: deviceId,
      socket: socket,
      logMessage: "Client $deviceId disconnected. Total clients: {count}",
    );
  }

  @visibleForTesting
  void recordIdentifyAckForTest({
    required String deviceId,
    required String? requestId,
    required DateTime acknowledgedAt,
  }) {
    _recordIdentifyAck(
      deviceId: deviceId,
      requestId: requestId,
      acknowledgedAt: acknowledgedAt,
    );
  }

  Future<NetworkSnapshot> _getMasterNetworkSnapshot() async {
    try {
      _masterNetworkSnapshot = await _masterNetworkSnapshotCache.current();
    } catch (e) {
      LogService.instance.registerLog("Could not refresh master network: $e");
    }

    return _masterNetworkSnapshot ??
        const NetworkSnapshot(
          isWifiActive: false,
          source: "master-unavailable",
          warnings: ["Master network snapshot unavailable."],
        );
  }

  /// Starts a periodic check for inactive clients based on heartbeat timestamps.
  void _startHeartbeatCheck() {
    _heartbeatCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      final inactiveClients = _lastHeartbeat.keys.where((deviceId) {
        final lastSeen = _lastHeartbeat[deviceId];
        return lastSeen == null ||
            now.difference(lastSeen).inSeconds > inactivityThreshold;
      }).toList();

      for (var deviceId in inactiveClients) {
        _clients.remove(deviceId);
        _lastHeartbeat.remove(deviceId);
        _markClientDisconnected(deviceId);
        LogService.instance
            .registerLog("Client $deviceId removed due to inactivity.");

        // Notify disconnection to callback if defined
        if (onClientRemoved != null) {
          onClientRemoved!(deviceId, inactivityThreshold);
        }
      }

      _notifyClientCount();
    });
  }

  void _stopHeartbeatCheck() {
    _heartbeatCheckTimer?.cancel();
    _heartbeatCheckTimer = null;
  }

  void _notifyClientCount() {
    if (onClientCountChange != null) {
      onClientCountChange!(_clients.length);
    }
  }

  List<String> getConnectedDeviceIds() {
    return _clients.keys.toList();
  }

  List<ConnectedDeviceInfo> getConnectedDeviceInfos() {
    return sortConnectedDeviceInfos(_clientInfo.values);
  }

  DateTime? get serverStartedAt => _serverStartedAt;

  /// Saves media data locally, either as a photo or video.
  ///
  /// - `binaryData`: The raw binary data of the media file.
  /// - `isPhoto`: Whether the media is a photo (`true`) or a video (`false`).
  /// Returns the file path where the media is saved.
  Future<String> _saveMediaLocally(Uint8List binaryData, bool isPhoto) async {
    LogService.instance.registerLog("Save media locally");

    return _sessionMediaStorage.saveReceivedMedia(
      binaryData: binaryData,
      sessionGuid: SessionManager.instance.sessionGuid,
      mediaType: isPhoto ? SessionMediaType.photo : SessionMediaType.video,
    );
  }

  void startNewSession(String sessionGuid) {
    // Init new session through SessionManager
    SessionManager.instance
        .joinSession(sessionGuid, null, deviceType: "Master");

    // Register logs
    LogService.instance
        .registerLog("New capture session started with GUID: $sessionGuid");

    // Notify slaves that session started
    final sessionStartedCommand = jsonEncode({
      "command": "sessionStarted",
      "sessionGuid": sessionGuid,
    });
    sendCommandToAll(sessionStartedCommand);
  }

  /// Sends a command to all connected slave devices.
  void sendCommandToAll(String message) {
    final sentCount = _sendCommandToEligibleClients(message);
    LogService.instance.registerLog(
        "Command sent to $sentCount eligible connected slave(s): $message");
  }

  Future<void> endCurrentSession() async {
    if (SessionManager.instance.currentSession != null) {
      final endedSessionGuid = SessionManager.instance.sessionGuid;

      // Register logs
      LogService.instance.registerLog(
          "Capture session with GUID: $endedSessionGuid ended and stored in history.");

      // End session through SessionManager
      await SessionManager.instance.endSession();

      // Notify slaves that session ended
      final sessionEndedCommand = jsonEncode({
        "command": "sessionEnded",
        if (endedSessionGuid != null && endedSessionGuid.isNotEmpty)
          "sessionGuid": endedSessionGuid,
      });
      sendCommandToAll(sessionEndedCommand);
    } else {
      LogService.instance.registerLog("No active session to end.");
    }
  }

  /// Sends a command to one or all connected slaves with optional device id.
  ///
  /// - `command`: The command to send (e.g., `takePhoto`, `startRecordingVideo`).
  /// - `deviceId`: If specified, sends the command to a single device.
  void sendCommand(String command, {String? deviceId}) {
    LogService.instance.registerLog("Sending command $command");

    if (_clients.isEmpty) {
      LogService.instance.registerLog(
          "No slave devices connected. Command '$command' not sent.");
    } else if (deviceId != null) {
      if (!_clients.containsKey(deviceId)) {
        LogService.instance.registerLog(
            "Command '$command' not sent. Slave $deviceId is not connected.");
        return;
      }

      final sentCount = _sendCommandToEligibleClients(
        command,
        deviceId: deviceId,
        commandLabel: command,
      );
      if (sentCount == 0) {
        final reason = _commandIneligibleReason(deviceId) ?? "eligibility";
        LogService.instance.registerLog(
            "Command '$command' blocked for slave $deviceId due to $reason.");
      } else {
        LogService.instance.registerLog(
            "Command '$command' sent to slave with deviceId: $deviceId.");
      }
    } else {
      final sentCount = _sendCommandToEligibleClients(
        command,
        commandLabel: command,
      );
      LogService.instance.registerLog(
          "Command '$command' sent to $sentCount eligible connected slave(s).");
    }
  }

  bool sendIdentifyCommand({
    required String deviceId,
    String? requestId,
    DateTime? requestedAt,
  }) {
    if (!_clients.containsKey(deviceId)) {
      LogService.instance.registerLog(
          "Identify command not sent. Slave $deviceId is not connected.");
      return false;
    }
    if (!_isNetworkEligible(deviceId)) {
      LogService.instance.registerLog(
          "Identify command blocked for slave $deviceId due to network mismatch.");
      return false;
    }

    final effectiveRequestedAt = requestedAt ?? DateTime.now().toUtc();
    final effectiveRequestId =
        requestId ?? "identify-${effectiveRequestedAt.microsecondsSinceEpoch}";
    final payload = {
      "command": "identifySlave",
      "requestId": effectiveRequestId,
      "requestedAt": effectiveRequestedAt.toIso8601String(),
    };
    _clients[deviceId]?.add(jsonEncode(payload));

    final previousInfo = _clientInfo[deviceId];
    if (previousInfo != null) {
      _clientInfo[deviceId] = previousInfo.copyWith(
        lastIdentifyRequestId: effectiveRequestId,
        lastIdentifyRequestedAt: effectiveRequestedAt,
      );
      _notifyClientCount();
    }

    LogService.instance.registerLog(
        "Identify command sent to slave with deviceId: $deviceId.");
    return true;
  }

  /// Schedules a command to be executed at a specific date and time.
  /// Sends the command along with the timestamp to all connected devices.
  void scheduleCommand(
    String command,
    DateTime scheduledTime, {
    String? deviceId,
    DateTime? masterTime,
  }) {
    // Convert the scheduled time to ISO 8601 format for standard communication
    final String scheduledTimeString = scheduledTime.toIso8601String();
    final String masterTimeString =
        (masterTime ?? DateTime.now().toUtc()).toIso8601String();
    final scheduledCommandPayload = {
      "type": "scheduledCommand",
      "command": command,
      "scheduledTime": scheduledTimeString,
      "masterTime": masterTimeString,
    };
    final scheduledCommandMessage = jsonEncode(scheduledCommandPayload);

    LogService.instance
        .registerLog("Scheduling command '$command' for $scheduledTimeString");

    if (_clients.isEmpty) {
      LogService.instance.registerLog(
          "No slave devices connected. Scheduled command '$command' not sent.");
    } else if (deviceId != null) {
      if (!_clients.containsKey(deviceId)) {
        LogService.instance.registerLog(
            "Scheduled command '$command' not sent. Slave $deviceId is not connected.");
        return;
      }

      final sentCount = _sendCommandToEligibleClients(
        scheduledCommandMessage,
        deviceId: deviceId,
        commandLabel: command,
      );
      if (sentCount == 0) {
        final reason = _commandIneligibleReason(deviceId) ?? "eligibility";
        LogService.instance.registerLog(
            "Scheduled command '$command' blocked for slave $deviceId due to $reason.");
      } else {
        LogService.instance.registerLog(
            "Scheduled command '$command' sent to slave with deviceId: $deviceId.");
      }
    } else {
      final sentCount = _sendCommandToEligibleClients(
        scheduledCommandMessage,
        commandLabel: command,
      );
      LogService.instance.registerLog(
          "Scheduled command '$command' sent to $sentCount eligible connected slave(s).");
    }
  }

  /// Stops the WebSocket server and cleans up all connections.
  void stopServer() {
    // Transport cleanup only; callers must end the active capture session
    // through endCurrentSession() when they intend to close the session.
    _stopRequested = true;
    final server = _server;
    _server = null;

    // Clean any client just in case
    for (var client in _clients.values) {
      client.close(WebSocketStatus.normalClosure, "Server shutting down");
    }

    unawaited(server?.close(force: true));
    _clients.clear();
    _lastHeartbeat.clear(); // Clean heartbeat registry
    _clientInfo.clear();
    _stopHeartbeatCheck(); // Stop timer
    LogService.instance.registerLog("WebSocket Server stopped");
    _notifyClientCount();
  }

  int _sendCommandToEligibleClients(
    String message, {
    String? deviceId,
    String? commandLabel,
  }) {
    if (deviceId != null) {
      final client = _clients[deviceId];
      if (client == null || !_isCommandEligible(deviceId)) {
        return 0;
      }

      client.add(message);
      return 1;
    }

    var sentCount = 0;
    for (var entry in _clients.entries) {
      final reason = _commandIneligibleReason(entry.key);
      if (reason != null) {
        LogService.instance.registerLog(
            "Command '${commandLabel ?? message}' skipped for slave ${entry.key} due to $reason.");
        continue;
      }

      entry.value.add(message);
      sentCount += 1;
    }
    return sentCount;
  }

  bool _isCommandEligible(String deviceId) {
    return _commandIneligibleReason(deviceId) == null;
  }

  bool _isNetworkEligible(String deviceId) {
    final info = _clientInfo[deviceId];
    return info?.networkStatus != ConnectedDeviceNetworkStatus.wrongNetwork;
  }

  String? _commandIneligibleReason(String deviceId) {
    if (!_isNetworkEligible(deviceId)) {
      return "network mismatch";
    }

    final info = _clientInfo[deviceId];
    final sessionStatus = info?.sessionStatus(
      masterSessionGuid: SessionManager.instance.sessionGuid,
    );
    if (sessionStatus == "different") {
      return "session mismatch";
    }

    return null;
  }
}
