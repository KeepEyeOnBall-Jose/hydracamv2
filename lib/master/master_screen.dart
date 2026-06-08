import "dart:io";

import "package:flutter/material.dart";
import "package:video_player/video_player.dart"; // Add video_player dependency in pubspec.yaml

import "../automation/automation_bridge.dart";
import "../automation/automation_config.dart";
import "../constants.dart" as constants;
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../screens/master_video_recording_screen.dart";
import "../screens/previous_sessions_screen.dart";
import "../screens/role_selection_screen.dart";
import "../screens/sports_centers_screen.dart";
import "../services/alert_utils.dart";
import "../services/camera_service_singleton.dart";
import "../services/device_service.dart";
import "../services/hydracam_api_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_manager.dart";
import "../services/settings_service.dart";
import "../services/storage_service.dart";
import "../services/user_service.dart";
import "../widgets/add_gallery_media_button.dart";
import "../widgets/animated_countdown_timer.dart";
import "../widgets/court_selection_widget.dart";
import "../widgets/hydra_cam_app_bar.dart";
import "../widgets/media_list_widget.dart";
import "../widgets/session_info_widget.dart";
import "master_announcer.dart";
import "connected_client_automation_payload.dart";
import "master_server.dart";

class MasterScreen extends StatefulWidget {
  const MasterScreen({super.key});

  @override
  MasterScreenState createState() => MasterScreenState();
}

class MasterScreenState extends State<MasterScreen> {
  late final MasterServer _server;
  final MasterAnnouncer _announcer = MasterAnnouncer(); // Broadcast announcer
  final HydraCamApiService _apiService =
      HydraCamApiService(); // API service instance
  final Map<String, AutomationHandler> _automationHandlers = {};

  int connectedClients = 0; // To display connected clients count
  bool isRecording = false;
  bool get _recordingActive =>
      isRecording ||
      _server.cameraService.isRecording ||
      (_server.cameraService.controller?.value.isRecordingVideo ?? false);
  bool _isRecordingTransitioning =
      false; // Track if recording state is changing
  // String? sessionGuid; // Store the session GUID from the API (Now from Session Manager)
  bool get sessionActive => SessionManager
      .instance.isSessionActive; // TODO: Extract to session manager??
  String? selectedCourtName; // Name of the selected Court
  String?
      selectedCourtGuid; // GUID of the selected Court (TODO: To be improved)

  // Getters for SessionManager photos and videos
  List<CapturedPhoto> get photos =>
      SessionManager.instance.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos =>
      SessionManager.instance.currentSession?.capturedVideos ?? [];

  List<String> getConnectedDevices() {
    return _server.getConnectedDeviceIds();
  }

  List<ConnectedDeviceInfo> getConnectedDeviceInfos() {
    return _server.getConnectedDeviceInfos();
  }

  // Processing indicators to prevent user from spamming buttons
  bool isProcessingEndSession = false; // To block button "End Session"
  bool isProcessingStartSession = false; // To block button "Start Session"
  bool isProcessingTakePhoto = false; // To block button "Take Photo"

  @override
  void initState() {
    super.initState();
    _announcer.startBroadcasting();
    // Use singletons directly instead of Provider
    _server = MasterServer(CameraServiceSingleton.instance);

    _server.onClientCountChange = (count) {
      if (mounted) {
        setState(() {
          connectedClients = count;
        });
      }
    };
    _server.onMediaReceived = (media) {
      setState(() {});
    };
    // Configure callback to notify disconnection
    _server.onClientRemoved = (deviceId, inactivityThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Client $deviceId disconnected after $inactivityThreshold seconds of inactivity.",
          ),
        ),
      );
    };
    _server.startServer();

    if (automationEnabled) {
      _registerAutomationHandlers();
      // Register callback for automation bridge to get recording state
      AutomationBridge.instance.getRecordingState = () => _recordingActive;
    }
  }

  @override
  void dispose() {
    if (automationEnabled && _automationHandlers.isNotEmpty) {
      AutomationBridge.instance.unregisterCommandsIfCurrent(
        _automationHandlers,
      );
      _automationHandlers.clear();
    }
    try {
      // Nullify callbacks to prevent setState() after dispose
      _server.onClientCountChange = null;
      _server.onMediaReceived = null;
      _server.onClientRemoved = null;

      // Stop server and announcer
      _server.stopServer();
      _announcer.stopBroadcasting();

      // TODO: Handle session ending if necessary
    } catch (e) {
      LogService.instance.registerLog("Error during dispose: $e");
    }
    super.dispose();
  }

  // Method to init a new session
  void _startOrEndSession() async {
    if (sessionActive) {
      await _endCurrentSession();
    } else {
      await _createSession();
    }
  }

  void _handleToggleRecordingButton() {
    _toggleRecording();
  }

  Future<void> _toggleRecording({
    bool showCountdown = true,
    bool suppressSnackbars = false,
    bool showPreview = true,
  }) async {
    if (StorageService.instance.isRecordingBlocked) {
      if (!suppressSnackbars) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Cannot start recording: Storage is critically low.")),
        );
      }
      LogService.instance
          .registerLog("Recording toggle blocked due to critical storage.");
      return;
    }

    if (_server.cameraService.recordingInterrupted.value) {
      if (!suppressSnackbars) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Recording already interrupted due to low storage.")),
        );
      }
      return;
    }

    LogService.instance.registerLog(
        "PRESSED TOGGLE RECORDING. IS RECORDING = $_recordingActive");

    final timerDuration = await SettingsService.getTimerDuration();
    final DateTime scheduledTime =
        DateTime.now().add(Duration(seconds: timerDuration));
    final String command =
        _recordingActive ? "stopRecordingVideo" : "startRecordingVideo";

    if (!mounted) return;
    if (showCountdown) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AnimatedCountdownTimer(
          duration: scheduledTime.difference(DateTime.now()).inMilliseconds,
          onComplete: () => Navigator.of(context).pop(),
        ),
      );
    }

    _server.scheduleCommand(command, scheduledTime);
    await Future.delayed(scheduledTime.difference(DateTime.now()));

    if (!mounted) return;

    try {
      if (_recordingActive) {
        if (await SettingsService.getMasterShouldRecord()) {
          await _stopMasterRecordingVideo();
        } else {
          setState(() {
            isRecording = false;
          });
        }
      } else {
        if (await SettingsService.getMasterShouldRecord()) {
          final didStart =
              await _startMasterRecordingVideo(showPreview: showPreview);
          if (!didStart) {
            LogService.instance.registerLog(
                "Recording toggle did not start local master recording.");
          }
        } else {
          setState(() {
            isRecording = true;
          });
        }
      }
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Recording toggle failed: $error\n$stackTrace");
      if (!suppressSnackbars && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Recording command failed: ${_describeError(error)}"),
          ),
        );
      }
    }

    LogService.instance.registerLog(
        "Command '$command' finished executing by master at ${DateTime.now()}");
  }

  Future<void> _ensureRecordingState({required bool shouldRecord}) async {
    // Wait for any ongoing state transitions
    int waitCount = 0;
    while (_isRecordingTransitioning && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (shouldRecord == _recordingActive) {
      return;
    }

    _isRecordingTransitioning = true;
    try {
      await _toggleRecording(
        showCountdown: false,
        suppressSnackbars: true,
        showPreview: false,
      );

      // Wait for recording state to actually change (with timeout)
      waitCount = 0;
      while (_recordingActive != shouldRecord && waitCount < 300) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      if (_recordingActive != shouldRecord) {
        LogService.instance.registerLog(
            "Warning: Recording state did not change to $shouldRecord after 30s");
      }
    } finally {
      _isRecordingTransitioning = false;
    }
  }

  void _registerAutomationHandlers() {
    if (!automationEnabled) {
      return;
    }

    final handlers = <String, AutomationHandler>{
      "start_session": (payload) async {
        if (payload["localOnly"] == true) {
          final sessionGuid = payload["sessionGuid"] as String? ??
              "local-${DateTime.now().millisecondsSinceEpoch}";
          _server.startNewSession(sessionGuid);
          setState(() {});
        } else {
          await _createSession(
            suppressSnackbars: true,
            skipCourtSelectionWarning: true,
            overrideCourtGuid: payload["courtGuid"] as String?,
            overrideSessionId: payload["sessionId"] as String?,
          );
        }
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "start_local_session": (payload) async {
        _startLocalAutomationSession(payload["sessionId"] as String?);
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "connected_clients": (payload) async {
        return {
          ...buildConnectedClientAutomationPayload(
            _server.getConnectedDeviceInfos(),
            serverStartedAt: _server.serverStartedAt,
          ),
          "session": AutomationBridge.instance.buildSessionSnapshot(),
        };
      },
      "end_session": (payload) async {
        if (SessionManager.instance.sessionGuid?.startsWith("local-") ??
            false) {
          await _server.endCurrentSession();
          if (mounted) {
            setState(() {});
          }
        } else {
          await _endCurrentSession(
            requireConfirmation: false,
            suppressSnackbars: true,
          );
        }
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "take_photo": (payload) async {
        await _executeTakePhoto(
          showCountdown: payload["showCountdown"] as bool? ?? false,
          suppressSnackbars: true,
        );
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "list_cameras": (payload) async {
        final cameraService = _server.cameraService;
        await cameraService.initAvailableCameras();
        return {
          "isUsingMockCamera": cameraService.isUsingMockCamera,
          "selectedCameraIndex": cameraService.selectedCameraIndex,
          "cameras": cameraService.deviceCameras
              .map((camera) => {
                    "name": camera.name,
                    "lensDirection": camera.lensDirection.name,
                    "sensorOrientation": camera.sensorOrientation,
                  })
              .toList(),
        };
      },
      "start_recording": (payload) async {
        await _ensureRecordingState(shouldRecord: true);
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "stop_recording": (payload) async {
        await _ensureRecordingState(shouldRecord: false);
        return AutomationBridge.instance.buildSessionSnapshot();
      },
    };

    handlers.forEach(AutomationBridge.instance.registerCommand);
    _automationHandlers.addAll(handlers);
  }

  void _startLocalAutomationSession(String? sessionId) {
    final effectiveSessionId =
        sessionId ?? "automation-local-${DateTime.now().toIso8601String()}";
    final sessionGuid = "local-$effectiveSessionId";
    SessionManager.instance
        .startSession(sessionGuid, effectiveSessionId, deviceType: "Master");
    _server.startNewSession(sessionGuid);
    LogService.instance.registerLog(
        "Automation local session created with GUID: $sessionGuid");
    if (mounted) {
      setState(() {});
    }
  }

  String _describeError(Object error) {
    return error.toString().replaceFirst("Exception: ", "");
  }

  Future<bool> _startMasterRecordingVideo({bool showPreview = true}) async {
    LogService.instance.registerLog("Will record from master and show preview");
    try {
      await _server.cameraService.startRecordingVideo();
      if (!mounted) {
        return false;
      }
      setState(() {
        isRecording = true;
      });
      if (showPreview) {
        _showMasterVideoPreview();
      }
      return true;
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Master recording start failed: $error\n$stackTrace");
      if (mounted) {
        setState(() {
          isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("Could not start recording: ${_describeError(error)}"),
          ),
        );
      }
      return false;
    }
  }

  Future<CapturedVideo> _stopMasterRecordingVideo() async {
    // Send command to slaves before stopping from master
    _server.sendCommand("stopRecordingVideo");

    final String videoPath = await _server.cameraService.stopRecordingVideo();

    // Get the device ID
    final String deviceId = await DeviceIdService.getOrCreateDeviceId();

    // Add video to current session
    final startRecordingDate = _server.cameraService.videoStartRecordingDate;
    final endRecordingDate = _server.cameraService.videoEndRecordingDate;
    if (startRecordingDate == null || endRecordingDate == null) {
      throw StateError("Master recording timestamps are missing after stop. "
          "start=$startRecordingDate end=$endRecordingDate");
    }

    final receivedDate = DateTime.now();
    final capturedVideo = CapturedVideo(
      videoData: null,
      videoPath: videoPath,
      slaveDeviceId: deviceId,
      startRecordingDate: startRecordingDate,
      endRecordingDate: endRecordingDate,
      receivedDate: receivedDate,
    );

    SessionManager.instance.addVideo(capturedVideo);

    setState(() {
      isRecording = false; // Update recording state
    });

    // Do not show the dialog here
    // Return the captured video
    return capturedVideo;
  }

  /// Open the "camera" preview screen while recording and then return video and show preview.
  void _showMasterVideoPreview() async {
    // Move to recording preview screen and get recorded video
    final capturedVideo = await Navigator.push<CapturedVideo>(
      context,
      MaterialPageRoute(
        builder: (context) => MasterVideoRecordingScreen(
          cameraService: _server.cameraService,
          onStopRecording: _stopMasterRecordingVideo,
        ),
      ),
    );

    if (capturedVideo != null) {
      // Automatically show recorded video only if autoplay setting is active
      final bool autoplayEnabled =
          await SettingsService.getAutoplayVideoOnMaster();
      if (autoplayEnabled) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _showVideoDialog(capturedVideo, autoClose: true);
          }
        });
      }
    }
  }

  void _handleTakePhotoButton() {
    _executeTakePhoto(showCountdown: true);
  }

  Future<void> _executeTakePhoto({
    required bool showCountdown,
    bool suppressSnackbars = false,
  }) async {
    if (isProcessingTakePhoto) return;

    setState(() {
      isProcessingTakePhoto = true;
    });

    try {
      final timerDuration = await SettingsService.getTimerDuration();
      final DateTime scheduledTime =
          DateTime.now().add(Duration(seconds: timerDuration));

      if (!mounted) return;
      if (showCountdown) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AnimatedCountdownTimer(
            duration: scheduledTime.difference(DateTime.now()).inMilliseconds,
            onComplete: () => Navigator.of(context).pop(),
          ),
        );
      }

      _server.scheduleCommand("takePhoto", scheduledTime);
      await Future.delayed(scheduledTime.difference(DateTime.now()));

      if (!mounted) return;

      final bool shouldMasterRecord =
          await SettingsService.getMasterShouldRecord();
      if (shouldMasterRecord) {
        try {
          final String photoPath = await _server.cameraService.takePhoto();
          final String deviceId = await DeviceIdService.getOrCreateDeviceId();

          final capturedPhoto = CapturedPhoto(
            photoData: null,
            photoPath: photoPath,
            captureDate: DateTime.now(),
            receivedDate: DateTime.now(),
            slaveDeviceId: deviceId,
          );

          SessionManager.instance.addPhoto(capturedPhoto);
          setState(() {});

          if (!suppressSnackbars) {
            _showPhotoDialog(capturedPhoto, autoClose: true);
          }
        } catch (error, stackTrace) {
          LogService.instance
              .registerLog("Master photo capture failed: $error\n$stackTrace");
          if (!suppressSnackbars && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Could not take photo: ${_describeError(error)}"),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      if (!suppressSnackbars) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Photo scheduled for ${scheduledTime.toLocal()}")),
        );
      }

      LogService.instance
          .registerLog("Photo command executed by master at ${DateTime.now()}");
    } finally {
      if (mounted) {
        setState(() {
          isProcessingTakePhoto = false;
        });
      }
    }
  }

  void _showPhotoDialog(CapturedPhoto photo, {bool autoClose = false}) {
    AlertUtils.showMediaDialog(
      context: context,
      media: photo,
      isAutoCloseEnabled: autoClose,
      autoCloseSeconds: constants.secondsToClosePhoto,
    );
  }

  void _showVideoDialog(CapturedVideo video, {bool autoClose = false}) {
    AlertUtils.showMediaDialog(
      context: context,
      media: video,
      isAutoCloseEnabled: autoClose,
      autoCloseSeconds: constants.secondsToClosePhoto,
    );
  }

  // Displays the number of connected devices and opens a modal for details
  Widget _connectedDevicesWidget() {
    return GestureDetector(
      onTap: () => _showConnectedDevicesModal(context),
      child: Column(
        children: [
          Text(
            "Connected clients: $connectedClients",
            style: const TextStyle(fontSize: 16, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  Future<void> _createSession({
    bool suppressSnackbars = false,
    bool skipCourtSelectionWarning = false,
    String? overrideCourtGuid,
    String? overrideSessionId,
  }) async {
    if (isProcessingStartSession) return;

    setState(() {
      isProcessingStartSession = true;
    });

    try {
      final sessionId = overrideSessionId ?? DateTime.now().toIso8601String();

      if (!skipCourtSelectionWarning && selectedCourtGuid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No court selected. Proceeding without a court."),
            duration: Duration(seconds: 3),
          ),
        );
      }

      final String? userGuid = UserService().guid;
      final response = await _apiService.createSession(
        sessionId,
        courtGuid: overrideCourtGuid ?? selectedCourtGuid,
        userGuid: userGuid,
      );

      LogService.instance.registerLog("Response to create session: $response");

      if (!mounted) return;

      if (response != null) {
        final String sessionGuid = response["guid"];
        SessionManager.instance
            .startSession(sessionGuid, sessionId, deviceType: "Master");
        _server.startNewSession(sessionGuid);

        LogService.instance
            .registerLog("Session created with GUID: $sessionGuid");

        setState(() {});
        if (!suppressSnackbars && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("Session created successfully: $sessionGuid")),
          );
        }
      } else {
        if (!suppressSnackbars && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to create session")),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessingStartSession = false;
        });
      }
    }
  }

  Future<void> _endCurrentSession({
    bool requireConfirmation = true,
    bool suppressSnackbars = false,
  }) async {
    if (isProcessingEndSession) return;

    // If recording is active, stop and save video first
    if (_recordingActive) {
      LogService.instance
          .registerLog("Stopping active recording before ending session");
      try {
        if (await SettingsService.getMasterShouldRecord()) {
          await _stopMasterRecordingVideo();
        } else {
          setState(() {
            isRecording = false;
          });
        }
      } catch (e) {
        LogService.instance
            .registerLog("Error stopping recording before session end: $e");
      }
    }

    if (!mounted) return;
    setState(() {
      isProcessingEndSession = true;
    });

    try {
      bool proceed = true;
      if (requireConfirmation) {
        final bool? confirmEnd = await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("End Current Session"),
              content: const Text(
                  "Are you sure you want to end the current session?"),
              actions: [
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: const Text("End Session"),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        );
        proceed = confirmEnd ?? false;
      }

      if (!proceed) {
        return;
      }

      if (SessionManager.instance.currentSession != null) {
        final bool success =
            await _apiService.endSession(SessionManager.instance.sessionGuid!);

        if (!mounted) return;

        if (success) {
          await _server.endCurrentSession();
          if (!mounted) return;
          setState(() {});
          if (!suppressSnackbars) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Capture session ended")),
            );
          }
        } else {
          if (!suppressSnackbars && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("Failed to end session on the server")),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessingEndSession = false;
        });
      }
    }
  }

  // Method to show a modal with the connected device IDs
  void _showConnectedDevicesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final List<ConnectedDeviceInfo> devices = getConnectedDeviceInfos();
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Connected Devices",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (devices.isNotEmpty)
                ...devices.map((device) {
                  final network = device.networkSnapshot;
                  final ssid = NetworkInfoService.formatSsidLabel(network);
                  final localIp = network?.ipAddress ?? "No reported IP";
                  final subnet =
                      network?.effectiveSubnetSignature ?? "Subnet unknown";
                  final remoteIp = device.remoteIp ?? "Remote IP unknown";
                  return ListTile(
                    title: Text(
                        "${device.shortDeviceId} · ${device.networkStatus.label}"),
                    subtitle: Text(
                      "Device ID: ${device.deviceId}\n"
                      "SSID: $ssid\n"
                      "Device IP: $localIp | Remote: $remoteIp\n"
                      "Subnet: $subnet",
                    ),
                    isThreeLine: true,
                    leading: Icon(
                      device.networkStatus ==
                              ConnectedDeviceNetworkStatus.wrongNetwork
                          ? Icons.warning
                          : Icons.wifi,
                      color: device.networkStatus ==
                              ConnectedDeviceNetworkStatus.wrongNetwork
                          ? Colors.red
                          : Colors.green,
                    ),
                  );
                })
              else if (getConnectedDevices().isNotEmpty)
                ...getConnectedDevices().map((deviceId) => ListTile(
                      title: Text("Device ID: $deviceId"),
                      subtitle: const Text("Network details unavailable"),
                    ))
              else
                const Center(child: Text("No connected devices")),
            ],
          ),
        );
      },
    );
  }

  // Build the initial UI when no session is active
  Widget _buildInitialUI() {
    // Order courts and centers for widget
    final Map<String, List<Map<String, String>>> sortedGroupedCourts = {
      for (var entry in (constants.groupedCourts.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) // Order centers
          )
        entry.key: entry.value
          ..sort((a, b) => a["name"]!.compareTo(b["name"]!)) // Order courts
    };

    // Compute button width based on orientation
    final buttonWidth = MediaQuery.of(context).orientation ==
            Orientation.portrait
        ? MediaQuery.of(context).size.width * 0.8 // 80% width when vertical
        : MediaQuery.of(context).size.width * 0.4; // 40% width when horizontal

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height, // Full screen height
            minWidth: MediaQuery.of(context).size.width),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Connected devices widget at the top
                _connectedDevicesWidget(),
                const SizedBox(height: 20),
                // Court selection widget with consistent width
                SizedBox(
                  width: buttonWidth,
                  child: CourtSelectionWidget(
                    groupedCourts: sortedGroupedCourts,
                    onCourtSelected: (selectedName, selectedGuid) {
                      setState(() {
                        selectedCourtName = selectedName;
                        selectedCourtGuid = selectedGuid;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // Buttons with consistent width and spacing
                SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed:
                        isProcessingStartSession ? null : _startOrEndSession,
                    child: isProcessingStartSession
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text("Start Session"),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => SportsCentersScreen()),
                    ),
                    child: const Text("Or... Load a Previous One"),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const PreviousSessionsScreen()),
                      );
                    },
                    child: const Text("View Local Sessions"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build the UI when a session is active
  Widget _buildSessionUI() {
    final String? sessionGuid = SessionManager.instance.sessionGuid;

    // Compute button width for vertical layout
    final buttonWidth =
        MediaQuery.of(context).orientation == Orientation.portrait
            ? MediaQuery.of(context).size.width * 0.8 // 80% width in portrait
            : MediaQuery.of(context).size.width * 0.4; // 40% width in landscape

    final double buttonDistance =
        MediaQuery.of(context).orientation == Orientation.portrait ? 10 : 5;

    // Buttons and connected devices widget
    final Widget controls = Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Connected devices widget
        _connectedDevicesWidget(),
        SizedBox(height: buttonDistance * 2),
        // Buttons
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: sessionGuid != null && !isProcessingTakePhoto
                ? _handleTakePhotoButton
                : null,
            child: isProcessingTakePhoto
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text("Take Photo"),
          ),
        ),
        SizedBox(height: buttonDistance),
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed:
                sessionGuid != null ? _handleToggleRecordingButton : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _recordingActive ? Colors.red : Colors.green,
            ),
            child:
                Text(_recordingActive ? "Stop Recording" : "Start Recording"),
          ),
        ),
        SizedBox(height: buttonDistance),
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: isProcessingEndSession || sessionGuid == null
                ? null
                : _endCurrentSession,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: isProcessingEndSession
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text("End Session"),
          ),
        ),
        SizedBox(height: buttonDistance),
        SizedBox(
          width: buttonWidth,
          child: AddGalleryMediaButton(enabled: !_recordingActive),
        ),
      ],
    );

    // Media list widget
    final Widget mediaList = MediaListWidget(
      photos: photos,
      videos: videos,
      onPhotoTap: (photo) =>
          _showPhotoDialog(photo, autoClose: false), // No auto-close
      onVideoTap: (video) =>
          _showVideoDialog(video, autoClose: false), // No auto-close
      showPlaceholder: true,
    );

    // Adjust layout based on orientation
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      // Vertical layout: controls and media list stacked
      return Column(
        children: [
          IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: controls,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: mediaList,
            ),
          ),
        ],
      );
    } else {
      // Horizontal layout: controls on the left, media list on the right
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: controls,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: mediaList,
            ),
          ),
        ],
      );
    }
  }

  // Build the final widget for the whole screen
  @override
  Widget build(BuildContext context) {
    final String? sessionGuid = SessionManager.instance.sessionGuid;

    return PopScope(
      canPop: false, // We handle back navigation ourselves
      onPopInvokedWithResult: (didPop, result) {
        if (_recordingActive) return; // Ignore back while recording

        // Handle the back button press
        _server.stopServer();
        _announcer.stopBroadcasting();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        );
      },
      child: Scaffold(
        appBar: HydraCamAppBar(
          title: "HydraCam - Master Control",
          onBack: () {
            _server.stopServer();
            _announcer.stopBroadcasting();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const RoleSelectionScreen()),
            );
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display session active status at the top
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SessionInfoWidget(
                sessionDisplay: sessionActive
                    ? "Session Active: $sessionGuid"
                    : "No active session",
              ),
            ),
            // Expanded widget to allow content to scroll if necessary
            Expanded(
              child: Center(
                child: sessionActive ? _buildSessionUI() : _buildInitialUI(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// VideoPlayerScreen - A widget to play video using the video_player plugin.
class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;

  const VideoPlayerScreen({super.key, required this.videoPath});

  @override
  VideoPlayerScreenState createState() => VideoPlayerScreenState();
}

class VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {}); // Refresh to show the video
        _controller.play();
      });
    SessionManager.instance.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    // This will be triggered whenever SessionManager calls notifyListeners()
    if (mounted) {
      setState(() {
        // Just to rebuild
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_controller.value.isInitialized)
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        else
          const CircularProgressIndicator(),
      ],
    );
  }
}
