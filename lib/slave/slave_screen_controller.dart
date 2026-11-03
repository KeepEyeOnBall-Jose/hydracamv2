import "dart:async";
import "package:camera/camera.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "../constants.dart" as constants;
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_manager.dart";
import "slave_client.dart";
import "master_discovery.dart";

typedef NetworkReadinessLoader = Future<NetworkReadinessResult> Function();

typedef SlaveConnectionClientFactory = SlaveConnectionClient Function(
  String serverAddress, {
  Function(String command, DateTime scheduledTime)? onScheduledCommand,
  Function(String path)? onPhotoTaken,
  VoidCallback? onRecordingStarted,
  VoidCallback? onRecordingStopped,
});

typedef MasterDiscoveryFactory = MasterDiscovery Function(
  void Function(String masterIp) onMasterDiscovered,
);

/// Non-presentation logic for the slave role: owns the [SlaveConnectionClient]
/// lifecycle, master discovery/registration, connection/reconnection state,
/// network-readiness gating, and capture (recording) state.
///
/// The screen owns this controller, drives it via intent methods, reads its
/// state through the read-only getters, and rebuilds on [notifyListeners].
/// Presentation-only reactions (dialogs, navigation, screen dimming, the
/// identify overlay) are delegated back to the screen through the settable
/// hook callbacks below.
class SlaveScreenController extends ChangeNotifier {
  SlaveScreenController({
    this.isAutoMode = false,
    this.preferredMasterIp,
    this.forceSlaveMode = false,
    NetworkReadinessLoader? networkReadinessLoader,
    SlaveConnectionClientFactory? slaveClientFactory,
    MasterDiscoveryFactory? masterDiscoveryFactory,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  })  : _networkReadinessLoader = networkReadinessLoader,
        _slaveClientFactory = slaveClientFactory,
        _masterDiscoveryFactory = masterDiscoveryFactory,
        _connectivityChanges = connectivityChanges;

  static const String _identifyAcknowledgedStatus =
      "Identify acknowledged to master.";

  // Mode that controls if we entered here manually or on app init.
  // If is auto mode, after some time without finding master will move
  // automatically to master screen.
  final bool isAutoMode;
  final String? preferredMasterIp;
  final bool forceSlaveMode;

  final NetworkReadinessLoader? _networkReadinessLoader;
  final SlaveConnectionClientFactory? _slaveClientFactory;
  final MasterDiscoveryFactory? _masterDiscoveryFactory;
  final Stream<List<ConnectivityResult>>? _connectivityChanges;

  // Presentation hooks wired by the owning screen.
  void Function(String command, DateTime scheduledTime)? onScheduledCommand;
  void Function(String path)? onPhotoTaken;
  VoidCallback? onRecordingStarted;
  VoidCallback? onRecordingStopped;
  VoidCallback? onIdentifyAcknowledged;
  VoidCallback? onAutoPromote;

  SlaveConnectionClient? _client;
  StreamSubscription<String>?
      _statusSubscription; // Subscription to listen to status updates
  StreamSubscription<bool>?
      _connectionStatusSubscription; // Subscription to listen to connection status
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  MasterDiscovery?
      _masterDiscovery; // Stored so we can properly dispose it on screen change

  Timer? autoModeTimer; // Timer for auto mode logic

  String _statusMessage = "Waiting for camera commands...";
  bool _isRecording = false;
  bool _isConnected = false; // Local variable for connection status
  bool _isStoppingRecording = false;

  bool _isCheckingNetwork = false;
  bool _isPreparingPreview = false;
  bool _isConnectingToMaster = false;
  String? _connectingMasterIp;
  String? _connectedMasterIp;
  NetworkReadinessResult? _networkReadiness;

  bool _disposed = false;

  // Read-only domain state exposed to the screen.
  String get statusMessage => _statusMessage;
  bool get isRecording => _isRecording;
  bool get isConnected => _isConnected;
  bool get isStoppingRecording => _isStoppingRecording;
  CameraController? get cameraController => _client?.cameraController;

  // Getters for SessionManager photos and videos.
  List<CapturedPhoto> get photos =>
      SessionManager.instance.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos =>
      SessionManager.instance.currentSession?.capturedVideos ?? [];

  /// Starts discovery, connectivity monitoring, and session tracking. Mirrors
  /// the slave screen's original `initState` wiring.
  void start() {
    final masterDiscoveryFactory = _masterDiscoveryFactory ??
        (onMasterDiscovered) => MasterDiscovery(
              onMasterDiscovered: onMasterDiscovered,
            );
    _masterDiscovery = masterDiscoveryFactory(
      (masterIp) => unawaited(_connectToMaster(masterIp)),
    );

    final connectivityChanges = _connectivityChanges;
    if (connectivityChanges != null ||
        defaultTargetPlatform != TargetPlatform.linux) {
      _networkSubscription =
          (connectivityChanges ?? NetworkInfoService.connectivityChanges)
              .listen(
        (_) async {
          await _startNetworkAwareDiscovery();
        },
        onError: (Object error, StackTrace stackTrace) {
          LogService.instance.registerError(
            "Connectivity change listener failed",
            error,
            stackTrace,
          );
        },
      );
    } else {
      LogService.instance.registerLog(
        "Skipping connectivity change listener on linux; "
        "network readiness will be checked on demand.",
      );
    }
    _startNetworkAwareDiscovery();

    SessionManager.instance.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void> _startNetworkAwareDiscovery() async {
    if (_disposed) {
      return;
    }
    if (_isCheckingNetwork) {
      return;
    }

    _isCheckingNetwork = true;
    if (_shouldFastConnectToPreferredMaster) {
      try {
        await _connectToMaster(
          preferredMasterIp!,
          skipNetworkReadiness: true,
        );
      } finally {
        _isCheckingNetwork = false;
      }
      return;
    }

    if (!_disposed && !_isConnected) {
      _statusMessage = "Checking Wi-Fi and local network...";
      notifyListeners();
    }

    try {
      final readiness = await _loadNetworkReadiness();
      _networkReadiness = readiness;

      if (!readiness.canUseLocalControl) {
        autoModeTimer?.cancel();
        autoModeTimer = null;
        _client?.disconnect();
        _client = null;
        await _masterDiscovery?.stopListening();
        if (!_disposed) {
          _isConnected = false;
          _statusMessage = readiness.message;
          notifyListeners();
        }
        LogService.instance.registerLog(
            "Slave network readiness blocked: ${readiness.message}");
        return;
      }

      if (!_disposed && !_isConnected) {
        _statusMessage = "Network ready. Searching for master...";
        notifyListeners();
      }

      if (_isConnected) {
        return;
      }

      if (preferredMasterIp != null) {
        await _connectToMaster(preferredMasterIp!);
      } else {
        await _masterDiscovery?.startListening();
        _scheduleAutoPromoteIfNeeded();
      }
    } catch (e) {
      LogService.instance.registerLog("Network readiness check failed: $e");
      if (!_disposed && !_isConnected) {
        _statusMessage = "Unable to check Wi-Fi readiness: $e";
        notifyListeners();
      }
    } finally {
      _isCheckingNetwork = false;
    }
  }

  bool get _shouldFastConnectToPreferredMaster =>
      forceSlaveMode && preferredMasterIp != null;

  Future<NetworkReadinessResult> _loadNetworkReadiness() async {
    final loader = _networkReadinessLoader;
    if (loader != null) {
      return loader();
    }
    final snapshot = await NetworkInfoService.getCurrentSnapshot();
    return NetworkInfoService.evaluateLocalControlReadiness(
      snapshot,
    );
  }

  SlaveConnectionClient _createSlaveClient(
    String serverAddress, {
    Function(String command, DateTime scheduledTime)? onScheduledCommand,
    Function(String path)? onPhotoTaken,
    VoidCallback? onRecordingStarted,
    VoidCallback? onRecordingStopped,
  }) {
    return SlaveClient(
      serverAddress,
      onScheduledCommand: onScheduledCommand,
      onPhotoTaken: onPhotoTaken,
      onRecordingStarted: onRecordingStarted,
      onRecordingStopped: onRecordingStopped,
    );
  }

  void _scheduleAutoPromoteIfNeeded() {
    final bool shouldAutoPromote =
        isAutoMode && !forceSlaveMode && preferredMasterIp == null;
    if (!shouldAutoPromote || autoModeTimer != null) {
      return;
    }

    final activeSessionGuid = SessionManager.instance.sessionGuid?.trim();
    if (SessionManager.instance.isSessionActive &&
        activeSessionGuid != null &&
        activeSessionGuid.isNotEmpty) {
      if (!_disposed && !_isConnected) {
        _statusMessage =
            "Master unavailable; preserving active session $activeSessionGuid.";
        notifyListeners();
      }
      LogService.instance.registerLog(
        "Auto-promotion blocked while slave session $activeSessionGuid is active.",
      );
      return;
    }

    autoModeTimer = Timer(Duration(seconds: constants.timeToStopSearching), () {
      if (!_isConnected && _networkReadiness?.canUseLocalControl == true) {
        LogService.instance
            .registerLog("No master found, switching to Master mode.");
        cleanUpSlaveMode();
        onAutoPromote?.call();
      }
    });
  }

  Future<void> _connectToMaster(
    String masterIp, {
    bool skipNetworkReadiness = false,
  }) async {
    if (_disposed) {
      return;
    }
    if (_isConnectingToMaster && _connectingMasterIp == masterIp) {
      LogService.instance.registerLog(
        "Ignoring duplicate connection attempt to master at IP: $masterIp",
      );
      return;
    }
    if (_isConnected && _connectedMasterIp == masterIp) {
      LogService.instance.registerLog(
        "Already connected to master at IP: $masterIp",
      );
      return;
    }

    _isConnectingToMaster = true;
    _connectingMasterIp = masterIp;
    if (!skipNetworkReadiness) {
      late final NetworkReadinessResult readiness;
      try {
        readiness = await _loadNetworkReadiness();
      } catch (error, stackTrace) {
        _isConnectingToMaster = false;
        _connectingMasterIp = null;
        LogService.instance.registerError(
          "Connection to master at IP $masterIp failed during network readiness",
          error,
          stackTrace,
        );
        if (!_disposed && !_isConnected) {
          _statusMessage = "Unable to check Wi-Fi readiness: $error";
          notifyListeners();
        }
        return;
      }
      _networkReadiness = readiness;
      if (!readiness.canUseLocalControl) {
        _isConnectingToMaster = false;
        _connectingMasterIp = null;
        if (!_disposed) {
          _statusMessage = readiness.message;
          notifyListeners();
        }
        LogService.instance.registerLog(
            "Connection to master blocked by network readiness: ${readiness.message}");
        return;
      }
    } else {
      LogService.instance.registerLog(
          "Skipping slave network readiness for forced preferred master $masterIp.");
    }

    if (_disposed) {
      _isConnectingToMaster = false;
      _connectingMasterIp = null;
      return;
    }

    LogService.instance.registerLog("Connecting to master at IP: $masterIp");

    _statusSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _client?.disconnect();

    final clientFactory = _slaveClientFactory ?? _createSlaveClient;
    _client = clientFactory(
      "ws://$masterIp:4040/ws",
      onScheduledCommand: _handleScheduledCommand, // Handle scheduled commands
      onPhotoTaken: _handlePhotoTaken,
      onRecordingStarted: _handleRecordingStarted,
      onRecordingStopped: _handleRecordingStopped,
    );

    _statusSubscription = _client?.statusStream.listen(_handleStatusMessage);

    _connectionStatusSubscription =
        _client?.connectionStatusStream.listen((isConnected) {
      if (!_disposed) {
        _isConnected = isConnected;
        notifyListeners();
      }

      if (isConnected) {
        _connectedMasterIp = masterIp;
        _isConnectingToMaster = false;
        _connectingMasterIp = null;
      }

      if (isConnected && !_isRecording) {
        unawaited(_prepareCameraPreview());
      }

      if (!isConnected) {
        if (_disposed) {
          return;
        }
        LogService.instance
            .registerLog("Connection lost. Restarting discovery.");
        _isConnectingToMaster = false;
        _connectingMasterIp = null;
        _connectedMasterIp = null;
        _client?.disconnect();
        _client = null;
        _startNetworkAwareDiscovery();
      }
    });

    _client?.connect();
    _masterDiscovery?.stopListening();

    if (isAutoMode) {
      autoModeTimer?.cancel();
    }
  }

  void _handleScheduledCommand(String command, DateTime scheduledTime) {
    onScheduledCommand?.call(command, scheduledTime);
  }

  void _handlePhotoTaken(String path) {
    if (_disposed) {
      return;
    }
    _statusMessage = "Photo taken!";
    notifyListeners();
    LogService.instance.registerLog("Photo taken!!!");
    onPhotoTaken?.call(path);
  }

  void _handleStatusMessage(String message) {
    if (_disposed) {
      return;
    }

    final isIdentifyAcknowledgement = message == _identifyAcknowledgedStatus;
    _statusMessage = message;
    notifyListeners();

    if (isIdentifyAcknowledgement) {
      onIdentifyAcknowledged?.call();
    }
  }

  Future<void> _prepareCameraPreview() async {
    if (_isPreparingPreview) {
      return;
    }
    final client = _client;
    if (client == null) {
      return;
    }

    _isPreparingPreview = true;
    try {
      await client.prepareCameraPreview();
      if (!_disposed) {
        notifyListeners();
      }
    } finally {
      _isPreparingPreview = false;
    }
  }

  void _handleRecordingStarted() {
    if (_disposed) {
      return;
    }
    _isRecording = true; // Update recording flag
    notifyListeners();
    onRecordingStarted?.call();
  }

  void _handleRecordingStopped() {
    if (_disposed) {
      return;
    }
    _isRecording = false;
    _isStoppingRecording = false;
    _statusMessage = "Recording stopped.";
    notifyListeners();
    onRecordingStopped?.call();
    unawaited(_prepareCameraPreview());
  }

  Future<void> stopRecordingSafely() async {
    final client = _client;
    if (client == null || !_isRecording || _isStoppingRecording) {
      return;
    }

    _isStoppingRecording = true;
    _statusMessage = "Stopping recording...";
    notifyListeners();

    try {
      await client.stopRecordingLocally();
    } catch (error, stackTrace) {
      LogService.instance.registerError(
        "Slave stop recording control failed",
        error,
        stackTrace,
      );
      if (!_disposed) {
        _isStoppingRecording = false;
        _statusMessage = "Recording stop failed: $error";
        notifyListeners();
      }
    }
  }

  void cleanUpSlaveMode() {
    _statusSubscription?.cancel(); // Cancel the stream subscription
    _networkSubscription?.cancel();
    _client?.disconnect();
    _client = null;
    _isConnectingToMaster = false;
    _connectingMasterIp = null;
    _connectedMasterIp = null;
    autoModeTimer?.cancel();
    autoModeTimer = null;
    _masterDiscovery?.stopListening();
    _masterDiscovery = null;

    LogService.instance.registerLog("Cleaned up Slave mode.");
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _statusSubscription
          ?.cancel(); // Cancel the subscription to avoid memory leaks
      _connectionStatusSubscription?.cancel();
      _networkSubscription?.cancel();
      _client?.disconnect();
      _client = null;
      _isConnectingToMaster = false;
      _connectingMasterIp = null;
      _connectedMasterIp = null;
      autoModeTimer?.cancel();
      autoModeTimer = null;
      _masterDiscovery?.stopListening();
      _masterDiscovery = null;
    } catch (e) {
      LogService.instance.registerLog("Exception: $e");
    }

    // Remove listener
    SessionManager.instance.removeListener(_onSessionChanged);

    super.dispose();
  }
}
