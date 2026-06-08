import "dart:async";
import "package:camera/camera.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "../screens/role_selection_screen.dart";
import "../globals.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/alert_utils.dart";
import "../services/device_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_manager.dart";
import "../services/settings_service.dart";
import "slave_client.dart";
import "master_discovery.dart";
import "../widgets/add_gallery_media_button.dart";
import "../widgets/animated_countdown_timer.dart";
import "../widgets/hydra_cam_app_bar.dart";
import "../widgets/media_list_widget.dart";
import "../widgets/session_info_widget.dart";
import "../master/master_screen.dart";

typedef NetworkReadinessLoader = Future<NetworkReadinessResult> Function();

typedef SlaveConnectionClientFactory = SlaveConnectionClient Function(
  String serverAddress, {
  Function(String command, DateTime scheduledTime)? onScheduledCommand,
  Function(String path)? onPhotoTaken,
  VoidCallback? onRecordingStarted,
  VoidCallback? onRecordingStopped,
});

class SlaveScreen extends StatefulWidget {
  // Mode that controls if we entered here manually or on app init.
  // If is auto mode, after some time without finding master will move automatically to master screen
  final bool isAutoMode;
  final String? preferredMasterIp;
  final bool forceSlaveMode;
  final NetworkReadinessLoader? networkReadinessLoader;
  final SlaveConnectionClientFactory? slaveClientFactory;
  final Stream<List<ConnectivityResult>>? connectivityChanges;

  const SlaveScreen({
    super.key,
    this.isAutoMode = false,
    this.preferredMasterIp,
    this.forceSlaveMode = false,
    @visibleForTesting this.networkReadinessLoader,
    @visibleForTesting this.slaveClientFactory,
    @visibleForTesting this.connectivityChanges,
  }); // Default is manual mode

  @override
  SlaveScreenState createState() => SlaveScreenState();
}

class SlaveScreenState extends State<SlaveScreen> {
  SlaveConnectionClient? _client;
  StreamSubscription<String>?
      _statusSubscription; // Subscription to listen to status updates
  StreamSubscription<bool>?
      _connectionStatusSubscription; // Subscription to listen to connection status
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  String statusMessage = "Waiting for camera commands...";
  Timer? autoModeTimer; // Timer for auto mode logic
  bool isRecording = false;

  bool _isConnected = false; // Local variable for connection status

  Timer? dimTimer; // Timer for screen dimming
  int dimTime = 10; // Number of seconds before turning screen black
  bool isScreenDimmed = false; // To control the dimmed screen state
  bool _isCheckingNetwork = false;
  NetworkReadinessResult? _networkReadiness;

  // Getters for SessionManager photos and videos
  List<CapturedPhoto> get photos =>
      SessionManager.instance.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos =>
      SessionManager.instance.currentSession?.capturedVideos ?? [];

  MasterDiscovery?
      _masterDiscovery; // So we can store instance of master_discovery and properly dispose it on screen change

  @override
  void initState() {
    super.initState();

    // Master discovery and other initializations
    _masterDiscovery = MasterDiscovery(onMasterDiscovered: _connectToMaster);

    final connectivityChanges = widget.connectivityChanges;
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

    // Add listener
    SessionManager.instance.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    setState(() {});
  }

  Future<void> _startNetworkAwareDiscovery() async {
    if (!mounted) {
      return;
    }
    if (_isCheckingNetwork) {
      return;
    }

    _isCheckingNetwork = true;
    if (_shouldFastConnectToPreferredMaster) {
      try {
        await _connectToMaster(
          widget.preferredMasterIp!,
          skipNetworkReadiness: true,
        );
      } finally {
        _isCheckingNetwork = false;
      }
      return;
    }

    if (mounted && !_isConnected) {
      setState(() {
        statusMessage = "Checking Wi-Fi and local network...";
      });
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
        if (mounted) {
          setState(() {
            _isConnected = false;
            statusMessage = readiness.message;
          });
        }
        LogService.instance.registerLog(
            "Slave network readiness blocked: ${readiness.message}");
        return;
      }

      if (mounted && !_isConnected) {
        setState(() {
          statusMessage = "Network ready. Searching for master...";
        });
      }

      if (_isConnected) {
        return;
      }

      if (widget.preferredMasterIp != null) {
        await _connectToMaster(widget.preferredMasterIp!);
      } else {
        await _masterDiscovery?.startListening();
        _scheduleAutoPromoteIfNeeded();
      }
    } catch (e) {
      LogService.instance.registerLog("Network readiness check failed: $e");
      if (mounted && !_isConnected) {
        setState(() {
          statusMessage = "Unable to check Wi-Fi readiness: $e";
        });
      }
    } finally {
      _isCheckingNetwork = false;
    }
  }

  bool get _shouldFastConnectToPreferredMaster =>
      widget.forceSlaveMode && widget.preferredMasterIp != null;

  Future<NetworkReadinessResult> _loadNetworkReadiness() async {
    final loader = widget.networkReadinessLoader;
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
    final bool shouldAutoPromote = widget.isAutoMode &&
        !widget.forceSlaveMode &&
        widget.preferredMasterIp == null;
    if (!shouldAutoPromote || autoModeTimer != null) {
      return;
    }

    autoModeTimer = Timer(Duration(seconds: timeToStopSearching), () {
      if (!_isConnected && _networkReadiness?.canUseLocalControl == true) {
        LogService.instance
            .registerLog("No master found, switching to Master mode.");
        _transitionToMasterScreen();
      }
    });
  }

  Future<void> _connectToMaster(
    String masterIp, {
    bool skipNetworkReadiness = false,
  }) async {
    if (!mounted) {
      return;
    }
    if (!skipNetworkReadiness) {
      final readiness = await _loadNetworkReadiness();
      _networkReadiness = readiness;
      if (!readiness.canUseLocalControl) {
        if (mounted) {
          setState(() {
            statusMessage = readiness.message;
          });
        }
        LogService.instance.registerLog(
            "Connection to master blocked by network readiness: ${readiness.message}");
        return;
      }
    } else {
      LogService.instance.registerLog(
          "Skipping slave network readiness for forced preferred master $masterIp.");
    }

    LogService.instance.registerLog("Connecting to master at IP: $masterIp");

    _statusSubscription?.cancel();
    _connectionStatusSubscription?.cancel();
    _client?.disconnect();

    final clientFactory = widget.slaveClientFactory ?? _createSlaveClient;
    _client = clientFactory(
      "ws://$masterIp:4040/ws",
      onScheduledCommand: _showCountdownTimer, // Handle scheduled commands
      onPhotoTaken: (path) async {
        if (!mounted) return;
        setState(() {
          statusMessage = "Photo taken!";
        });
        LogService.instance.registerLog("Photo taken!!!");

        final String deviceId = await DeviceIdService.getOrCreateDeviceId();

        if (!mounted) return;

        AlertUtils.showMediaDialog(
            context: context,
            media: CapturedPhoto(
              photoPath: path,
              photoData: null,
              captureDate: DateTime.now(),
              receivedDate: DateTime.now(),
              slaveDeviceId: deviceId,
            ),
            isAutoCloseEnabled: true,
            autoCloseSeconds: secondsToClosePhoto);
      },
      onRecordingStarted: _handleRecordingStarted,
      onRecordingStopped: _handleRecordingStopped,
    );

    _statusSubscription = _client?.statusStream.listen((message) {
      if (mounted) {
        setState(() {
          statusMessage = message;
        });
      }
    });

    _connectionStatusSubscription =
        _client?.connectionStatusStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }

      if (!isConnected) {
        if (!mounted) {
          return;
        }
        LogService.instance
            .registerLog("Connection lost. Restarting discovery.");
        _client?.disconnect();
        _client = null;
        _startNetworkAwareDiscovery();
      }
    });

    _client?.connect();
    _masterDiscovery?.stopListening();

    if (widget.isAutoMode) {
      autoModeTimer?.cancel();
    }
  }

  void _handleRecordingStarted() {
    if (mounted) {
      setState(() {
        isRecording = true; // Update recording flag
        _startDimTimer(); // Start dim timer in case we want to set screen black
      });
    }
  }

  void _handleRecordingStopped() {
    if (mounted) {
      setState(() {
        isRecording = false;
        isScreenDimmed = false;
        statusMessage = "Recording stopped.";
      });
      dimTimer?.cancel();
    }
  }

  void _startDimTimer() async {
    dimTimer?.cancel();
    if (await _getAutoOffSetting()) {
      dimTimer = Timer(Duration(seconds: dimTime), () {
        if (isRecording) {
          setState(() {
            isScreenDimmed = true;
          });
        }
      });
    }
  }

  void _resetDimTimer() async {
    setState(() {
      isScreenDimmed = false;
    });
    _startDimTimer();
  }

  Future<bool> _getAutoOffSetting() async {
    return await SettingsService.getScreenAutoOff();
  }

  void _transitionToMasterScreen() {
    // Stop any activity related to Slave
    _cleanUpSlaveMode();

    // Move to master screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MasterScreen()),
    );
  }

  void _cleanUpSlaveMode() {
    _statusSubscription?.cancel(); // Cancel the stream subscription
    _networkSubscription?.cancel();
    _client?.disconnect();
    _client = null;
    autoModeTimer?.cancel();
    autoModeTimer = null;
    _masterDiscovery?.stopListening();
    _masterDiscovery = null;

    LogService.instance.registerLog("Cleaned up Slave mode.");
  }

  /// Displays a countdown timer and executes the command after completion.
  void _showCountdownTimer(String command, DateTime scheduledTime) {
    final Duration delay = scheduledTime.difference(DateTime.now());

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnimatedCountdownTimer(
        duration: delay.inMilliseconds,
        onComplete: () {
          Navigator.of(context).pop(); // Close the dialog
        },
      ),
    );
  }

  @override
  void dispose() {
    try {
      dimTimer?.cancel();
      _statusSubscription
          ?.cancel(); // Cancel the subscription to avoid memory leaks
      _connectionStatusSubscription?.cancel();
      _networkSubscription?.cancel();
      _client?.disconnect();
      _client = null;
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

  Widget _buildStatusMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            statusMessage,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          if (!statusMessage.contains("stop") &&
              (statusMessage.contains("Taking") ||
                  statusMessage.contains("Recording")))
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Media list widget with placeholder enabled
    final Widget mediaList = MediaListWidget(
      photos: photos,
      videos: videos,
      onPhotoTap: _showPhotoDialog,
      onVideoTap: _showVideoDialog,
      showPlaceholder: true, // Enable placeholder
    );

    // Controls and camera preview widget
    final Widget controlsAndPreview = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SessionInfoWidget(
            sessionDisplay:
                SessionManager.instance.sessionGuid ?? "No active session",
          ),
        ),
        AddGalleryMediaButton(enabled: !isRecording),
        const SizedBox(height: 10),
        Expanded(
          child: _client?.cameraController != null
              ? ValueListenableBuilder<CameraValue>(
                  valueListenable: _client!.cameraController!,
                  builder: (context, cameraValue, child) {
                    return Stack(
                      children: [
                        if (isRecording &&
                            _client?.cameraController != null &&
                            _client!.cameraController!.value.isInitialized)
                          Positioned.fill(
                            child: CameraPreview(_client!.cameraController!),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  statusMessage,
                                  style: const TextStyle(fontSize: 18),
                                  textAlign: TextAlign.center,
                                ),
                                if (!statusMessage.contains("stop") &&
                                    (statusMessage.contains("Taking") ||
                                        statusMessage.contains("Recording")))
                                  const Padding(
                                    padding: EdgeInsets.only(top: 20),
                                    child: CircularProgressIndicator(),
                                  ),
                              ],
                            ),
                          ),
                        if (isRecording)
                          const Positioned(
                            bottom: 20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                "Recording...",
                                style:
                                    TextStyle(color: Colors.red, fontSize: 24),
                              ),
                            ),
                          ),
                      ],
                    );
                  })
              : Stack(
                  children: [
                    _buildStatusMessage(),
                    if (isRecording)
                      const Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            "Recording...",
                            style: TextStyle(color: Colors.red, fontSize: 24),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );

    // Adjust layout based on orientation
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      // Vertical layout: controls and media list stacked
      return GestureDetector(
          onTap: _resetDimTimer, // Reset dimming on user interaction
          child: Stack(
            children: [
              Scaffold(
                appBar: HydraCamAppBar(
                  title: "HydraCam - Slave Device",
                  onBack: () {
                    _cleanUpSlaveMode();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const RoleSelectionScreen()),
                    );
                  },
                ),
                body: Column(
                  children: [
                    Expanded(
                      flex: 2,
                      child: controlsAndPreview,
                    ),
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: mediaList,
                      ),
                    ),
                  ],
                ),
              ),
              if (isScreenDimmed)
                GestureDetector(
                  onTap: _resetDimTimer, // Wake up the screen
                  child: Container(
                    color: Colors.black,
                    child: const Center(
                      child: Text(
                        "Screen Off - Tap to wake",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ));
    } else {
      // Horizontal layout: controls on the left, media list on the right
      return GestureDetector(
        onTap: _resetDimTimer,
        child: Stack(
          children: [
            Scaffold(
              appBar: HydraCamAppBar(
                title: "HydraCam - Slave Device",
                onBack: () {
                  _cleanUpSlaveMode();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const RoleSelectionScreen()),
                  );
                },
              ),
              body: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: controlsAndPreview,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: mediaList,
                    ),
                  ),
                ],
              ),
            ),
            if (isScreenDimmed)
              GestureDetector(
                onTap: _resetDimTimer, // Wake up the screen
                child: Container(
                  color: Colors.black,
                  child: const Center(
                    child: Text(
                      "Screen Off - Tap to wake",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }

  void _showPhotoDialog(CapturedPhoto photo) {
    AlertUtils.showMediaDialog(
        context: context,
        media: photo,
        isAutoCloseEnabled: false, // Auto-close is disabled for slave screens
        autoCloseSeconds: secondsToClosePhoto);
  }

  void _showVideoDialog(CapturedVideo video) {
    AlertUtils.showMediaDialog(
      context: context,
      media: video,
      isAutoCloseEnabled: false, // Auto-close is disabled for slave screens
    );
  }
}
