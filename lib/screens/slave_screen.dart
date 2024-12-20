import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hydracam/screens/role_selection_screen.dart';
import '../globals.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/alert_utils.dart';
import '../services/device_service.dart';
import '../services/log_service.dart';
import '../services/session_manager.dart';
import '../services/settings_service.dart';
import '../slave/slave_client.dart';
import '../slave/master_discovery.dart';
import '../widgets/add_gallery_media_button.dart';
import '../widgets/animated_countdown_timer.dart';
import '../widgets/hydra_cam_app_bar.dart';
import '../widgets/media_list_widget.dart';
import '../widgets/session_info_widget.dart';
import 'master_screen.dart';

class SlaveScreen extends StatefulWidget {

  // Mode that controls if we entered here manually or on app init.
  // If is auto mode, after some time without finding master will move automatically to master screen
  final bool isAutoMode;
  const SlaveScreen({super.key, this.isAutoMode = false}); // Default is manual mode

  @override
  _SlaveScreenState createState() => _SlaveScreenState();
}

class _SlaveScreenState extends State<SlaveScreen> {
  SlaveClient? _client;
  StreamSubscription<String>? _statusSubscription; // Subscription to listen to status updates
  StreamSubscription<bool>? _connectionStatusSubscription; // Subscription to listen to connection status
  String statusMessage = "Waiting for camera commands...";
  Timer? autoModeTimer; // Timer for auto mode logic
  bool isRecording = false;

  bool _isConnected = false; // Local variable for connection status

  Timer? dimTimer; // Timer for screen dimming
  int dimTime = 10; // Number of seconds before turning screen black
  bool isScreenDimmed = false; // To control the dimmed screen state

  // Getters for SessionManager photos and videos
  List<CapturedPhoto> get photos => SessionManager.instance.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos => SessionManager.instance.currentSession?.capturedVideos ?? [];

  MasterDiscovery? _masterDiscovery; // So we can store instance of master_discovery and properly dispose it on screen change

  @override
  void initState() {
    super.initState();

    // Master discovery and other initializations
    _masterDiscovery = MasterDiscovery(onMasterDiscovered: (masterIp) {
      LogService.instance.registerLog("Connecting to master at IP: $masterIp");
      _client = SlaveClient(
        'ws://$masterIp:4040/ws',
        onScheduledCommand: _showCountdownTimer, // Handle scheduled commands
        onPhotoTaken: (path) async {
          if (!mounted) return;
          setState(() {
            statusMessage = "Photo taken!";
          });
          LogService.instance.registerLog("Photo taken!!!");

          final String deviceId = await DeviceIdService.getOrCreateDeviceId();

          // Use the unified dialog function with placeholder metadata to wrap photo into CapturePhoto
          AlertUtils.showMediaDialog(
              context: context,
              media: CapturedPhoto(
                photoPath: path,
                photoData: null,
                captureDate: DateTime.now(),
                receivedDate: DateTime.now(),
                slaveDeviceId: deviceId, // Populate as needed
              ),
              isAutoCloseEnabled: true, // No auto-close for slave
              autoCloseSeconds: secondsToClosePhoto
          );
        },
        onRecordingStarted: _handleRecordingStarted,
        onRecordingStopped: _handleRecordingStopped,
      );

      // Listen to the client's status stream
      _statusSubscription = _client?.statusStream.listen((message) {
        if (mounted) {
          setState(() {
            statusMessage = message;
          });
        }
      });

      // Listen to the client's connection status stream
      _connectionStatusSubscription = _client?.connectionStatusStream.listen((isConnected) {

        if (mounted) {
          setState(() {
            _isConnected = isConnected;
          });
        }

        if (!isConnected) {
          // Connection lost, restart discovery
          LogService.instance.registerLog("Connection lost. Restarting discovery.");
          _client?.disconnect();
          _client = null;
          _masterDiscovery?.startListening();
        }
      });

      // Connect to master
      _client?.connect();

      // Stop discovery once connected
      _masterDiscovery?.stopListening();

      if (widget.isAutoMode) {
        autoModeTimer?.cancel(); // Stop auto mode if master is found
      }
    });

    _masterDiscovery?.startListening();


    if (widget.isAutoMode) {
      // Automatically transition to MasterScreen if no master is found
      autoModeTimer = Timer(Duration(seconds: timeToStopSearching), () {
        if (!_isConnected) {
          LogService.instance.registerLog("No master found, switching to Master mode.");
          _transitionToMasterScreen();
        }
      });
    }


    // Add listener
    SessionManager.instance.addListener(_onSessionChanged);

  }

  void _onSessionChanged() {
    setState(() {});
  }

  void _handleRecordingStarted() {
    if(mounted){
      setState(() {
        isRecording = true; // Update recording flag
        _startDimTimer();   // Start dim timer in case we want to set screen black
      });
    }
  }

  void _handleRecordingStopped() {
    if (mounted) {
      setState(() {
        isRecording = false;
        isScreenDimmed = false;
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
    try{
      dimTimer?.cancel();
      _statusSubscription?.cancel(); // Cancel the subscription to avoid memory leaks
      _connectionStatusSubscription?.cancel();
      _client?.disconnect();
      _client = null;
      autoModeTimer?.cancel();
      autoModeTimer = null;
      _masterDiscovery?.stopListening();
      _masterDiscovery = null;
    }
    catch(e){
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
          if (statusMessage.contains("Taking") || statusMessage.contains("Recording"))
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
    Widget mediaList = MediaListWidget(
      photos: photos,
      videos: videos,
      onPhotoTap: _showPhotoDialog,
      onVideoTap: _showVideoDialog,
      showPlaceholder: true, // Enable placeholder
    );

    // Controls and camera preview widget
    Widget controlsAndPreview = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SessionInfoWidget(
            sessionDisplay: SessionManager.instance.sessionGuid ?? "No active session",
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
                          if (isRecording && _client?.cameraController != null && _client!.cameraController!.value.isInitialized)
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
                                  if (statusMessage.contains("Taking") || statusMessage.contains("Recording"))
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
                                  'Recording...',
                                  style: TextStyle(color: Colors.red, fontSize: 24),
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                )
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
                            'Recording...',
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
                    MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
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
        )
      );
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
                    MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
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
      autoCloseSeconds: secondsToClosePhoto
    );
  }

  void _showVideoDialog(CapturedVideo video) {
    AlertUtils.showMediaDialog(
      context: context,
      media: video,
      isAutoCloseEnabled: false, // Auto-close is disabled for slave screens
    );
  }

}
