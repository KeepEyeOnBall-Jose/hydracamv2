import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:video_player/video_player.dart"; // Add video_player dependency in pubspec.yaml

import "../app_theme.dart";
import "../constants.dart" as constants;
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../screens/camera_setup_preview_screen.dart";
import "../screens/master_video_recording_screen.dart";
import "../screens/previous_sessions_screen.dart";
import "../screens/role_selection_screen.dart";
import "../screens/sports_centers_screen.dart";
import "../services/alert_utils.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";
import "../services/session_naming_service.dart";
import "../services/session_manager.dart";
import "../services/settings_service.dart";
import "../widgets/add_gallery_media_button.dart";
import "../widgets/animated_countdown_timer.dart";
import "../widgets/camera_preview_widget.dart";
import "../widgets/court_selection_widget.dart";
import "../widgets/hydra_cam_app_bar.dart";
import "../widgets/hydracam_surface.dart";
import "../widgets/media_list_widget.dart";
import "../widgets/session_info_widget.dart";
import "master_announcer.dart";
import "master_screen_controller.dart";
import "master_server.dart";

class MasterScreen extends StatefulWidget {
  const MasterScreen({
    super.key,
    MasterServer? masterServer,
    MasterAnnouncer? announcer,
  })  : _masterServer = masterServer,
        _announcer = announcer;

  final MasterServer? _masterServer;
  final MasterAnnouncer? _announcer;

  @override
  MasterScreenState createState() => MasterScreenState();
}

class MasterScreenState extends State<MasterScreen> {
  late final MasterScreenController _controller;

  final TextEditingController sessionNameController = TextEditingController();
  bool sessionNameEditedManually = false;

  // Thin forwarders so the presentation methods below read the controller's
  // domain state without structural changes to the widget tree.
  int get connectedClients => _controller.connectedClients;
  bool get _recordingActive => _controller.recordingActive;
  bool get sessionActive => _controller.sessionActive;
  String get selectedActivityPreset => _controller.selectedActivityPreset;
  bool get isProcessingStartSession => _controller.isProcessingStartSession;
  bool get isProcessingEndSession => _controller.isProcessingEndSession;
  bool get isProcessingTakePhoto => _controller.isProcessingTakePhoto;
  List<CapturedPhoto> get photos => _controller.photos;
  List<CapturedVideo> get videos => _controller.videos;

  List<String> getConnectedDevices() {
    return _controller.getConnectedDeviceIds();
  }

  List<ConnectedDeviceInfo> getConnectedDeviceInfos() {
    return _controller.getConnectedDeviceInfos();
  }

  @override
  void initState() {
    super.initState();
    _controller = MasterScreenController(
      masterServer: widget._masterServer,
      announcer: widget._announcer,
    );
    _controller
      ..showMessage = _showMessage
      ..showCountdownDialog = _showCountdown
      ..confirmStartWithoutCourt = _confirmStartWithoutCourt
      ..confirmEndSession = _confirmEndSession
      ..showCameraSetupPreview = _showMasterCameraSetupPreview
      ..showMasterVideoPreview = _showMasterVideoPreview
      ..showPhotoDialog = _showPhotoDialog
      ..showVideoDialog = _showVideoDialog
      ..currentCustomSessionName = () => sessionNameController.text;
    _controller.addListener(_handleControllerChanged);
    _refreshGeneratedSessionName(force: true);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    sessionNameController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showMessage(String message, {Duration? duration}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  void _showCountdown(int durationMs) {
    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnimatedCountdownTimer(
        duration: durationMs,
        onComplete: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _handleToggleRecordingButton() {
    unawaited(_controller.toggleRecording());
  }

  String _describeError(Object error) {
    return error.toString().replaceFirst("Exception: ", "");
  }

  Future<bool> _showMasterCameraSetupPreview() async {
    try {
      await _controller.cameraService.prepareCameraPreview();
    } catch (error, stackTrace) {
      LogService.instance.registerLog(
          "Master setup preview camera init failed: $error\n$stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("Could not open camera setup: ${_describeError(error)}"),
          ),
        );
      }
      return false;
    }

    if (!mounted) {
      return false;
    }

    final controller = _controller.cameraService.controller;
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraSetupPreviewScreen(
          preview: controller == null
              ? null
              : CameraPreviewWidget(controller: controller),
          onStartRecording: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    return confirmed ?? false;
  }

  /// Open the "camera" preview screen while recording and then return video and show preview.
  Future<void> _showMasterVideoPreview() async {
    // Move to recording preview screen and get recorded video
    final capturedVideo = await Navigator.push<CapturedVideo>(
      context,
      MaterialPageRoute(
        builder: (context) => MasterVideoRecordingScreen(
          cameraService: _controller.cameraService,
          onStopRecording: _controller.stopMasterRecordingVideo,
        ),
      ),
    );

    if (!mounted || capturedVideo == null) {
      return;
    }

    // Automatically show recorded video only if autoplay setting is active
    final bool autoplayEnabled =
        await SettingsService.getAutoplayVideoOnMaster();
    if (!mounted || !autoplayEnabled) {
      return;
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _showVideoDialog(capturedVideo, autoClose: true);
      }
    });
  }

  void _handleTakePhotoButton() {
    unawaited(_controller.executeTakePhoto(showCountdown: true));
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
      child: HydraCamStatusChip(
        status: connectedClients > 0
            ? HydraCamStatusTone.active
            : HydraCamStatusTone.neutral,
        icon: connectedClients > 0 ? Icons.devices : Icons.devices_outlined,
        label: "Connected clients: $connectedClients",
      ),
    );
  }

  Future<bool> _confirmEndSession() async {
    final bool? confirmEnd = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("End Current Session"),
          content:
              const Text("Are you sure you want to end the current session?"),
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
    return confirmEnd ?? false;
  }

  // Method to show a modal with the connected device IDs
  void _showConnectedDevicesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final List<ConnectedDeviceInfo> devices = getConnectedDeviceInfos();
        final summary = summarizeConnectedDeviceInfos(devices);
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Known Devices",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(summary.label),
                  const SizedBox(height: 10),
                  if (devices.isNotEmpty)
                    ...devices.map((device) {
                      final network = device.networkSnapshot;
                      final ssid = NetworkInfoService.formatSsidLabel(network);
                      final localIp = network?.ipAddress ?? "No reported IP";
                      final subnet =
                          network?.effectiveSubnetSignature ?? "Subnet unknown";
                      final remoteIp = device.remoteIp ?? "Remote IP unknown";
                      final appVersion =
                          device.appVersion ?? "App version not reported";
                      final appBuildNumber = device.appBuildNumber;
                      final appLine = appBuildNumber == null
                          ? "App: $appVersion"
                          : "App: $appVersion+$appBuildNumber";
                      final hardwareLine =
                          "Hardware: ${device.hardwareLabel ?? 'not reported'}";
                      final isDisconnected = !device.isConnected;
                      final registeredLine =
                          "Registered: ${device.registeredAt.toLocal()}";
                      final lastSeenLine =
                          "Last seen: ${device.lastSeen.toLocal()}";
                      final disconnectedLine = device.disconnectedAt == null
                          ? ""
                          : "Disconnected: ${device.disconnectedAt!.toLocal()}\n";
                      final sessionLine =
                          "Session: ${device.sessionStatusLabel(masterSessionGuid: SessionManager.instance.sessionGuid)}";
                      final reportedSessionLine =
                          "Reported session: ${device.reportedSessionGuid ?? 'not reported'}";
                      final mediaLine =
                          _formatSessionMediaLine(device.sessionMedia);
                      final identifyLine =
                          "Identify: ${device.identifyStatusLabel}";
                      return ListTile(
                        title: Text("${device.shortDeviceId} · "
                            "${device.connectionStatusLabel} · "
                            "${device.networkStatusLabel}"),
                        subtitle: Text(
                          "Device ID: ${device.deviceId}\n"
                          "$appLine\n"
                          "$hardwareLine\n"
                          "SSID: $ssid\n"
                          "Device IP: $localIp | Remote: $remoteIp\n"
                          "Subnet: $subnet\n"
                          "$registeredLine\n"
                          "$lastSeenLine\n"
                          "Preview: ${device.previewStatusLabel} "
                          "(${device.previewTransportLabel})\n"
                          "$sessionLine\n"
                          "$reportedSessionLine\n"
                          "$mediaLine\n"
                          "$identifyLine\n"
                          "$disconnectedLine"
                          "${device.setupStatusLabel}",
                        ),
                        isThreeLine: true,
                        leading: Icon(
                          isDisconnected
                              ? Icons.link_off
                              : device.networkStatus ==
                                      ConnectedDeviceNetworkStatus.wrongNetwork
                                  ? Icons.warning
                                  : Icons.wifi,
                          color: isDisconnected
                              ? AppTheme.textTertiary
                              : device.networkStatus ==
                                      ConnectedDeviceNetworkStatus.wrongNetwork
                                  ? AppTheme.danger
                                  : AppTheme.accent,
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
            ),
          ),
        );
      },
    );
  }

  String _formatSessionMediaLine(Map<String, int>? sessionMedia) {
    if (sessionMedia == null) {
      return "Media: not reported";
    }

    final photos = sessionMedia["photoCount"] ?? 0;
    final videos = sessionMedia["videoCount"] ?? 0;
    final pending = sessionMedia["pendingUploadCount"] ?? 0;
    final uploaded = sessionMedia["uploadedCount"] ?? 0;

    return "Media: ${_formatCount(photos, "photo")}, "
        "${_formatCount(videos, "video")}, "
        "$pending pending, $uploaded uploaded";
  }

  String _formatCount(int count, String singular) {
    return "$count $singular${count == 1 ? "" : "s"}";
  }

  String _sessionDisplay() {
    return _controller.sessionDisplay;
  }

  void _refreshGeneratedSessionName({bool force = false}) {
    if (sessionNameEditedManually && !force) {
      return;
    }
    sessionNameController.text = _controller.generatedSessionName;
    sessionNameEditedManually = false;
  }

  double _actionButtonWidth(double maxWidth) {
    final availableWidth =
        !maxWidth.isFinite || maxWidth <= 0 ? 180.0 : maxWidth;
    if (availableWidth < 360) {
      return availableWidth;
    }
    if (availableWidth < 560) {
      return (availableWidth - 8) / 2;
    }
    return 168;
  }

  static const double _masterActionButtonHeight = 48;

  Widget _actionButton({
    required double width,
    required Widget icon,
    required String label,
    required VoidCallback? onPressed,
    ButtonStyle? style,
  }) {
    return SizedBox(
      width: width,
      height: _masterActionButtonHeight,
      child: ElevatedButton.icon(
        icon: icon,
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: onPressed,
        style: style,
      ),
    );
  }

  Future<bool> _confirmStartWithoutCourt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Start without court?"),
        content: const Text(
          "This session will not be attached to a court. Choose a court first "
          "unless this is a quick test.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Choose Court"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Start Without Court"),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // Build the initial UI when no session is active
  Widget _buildInitialUI() {
    // Order courts and centers for widget
    final Map<String, List<Map<String, String>>> sortedGroupedCourts = {
      for (var entry in (constants.groupedCourts.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) // Order centers
          )
        entry.key: [...entry.value]
          ..sort((a, b) => a["name"]!.compareTo(b["name"]!)) // Order courts
    };

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height,
          minWidth: MediaQuery.of(context).size.width,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth =
                    constraints.maxWidth < 560 ? constraints.maxWidth : 520.0;
                final buttonWidth = _actionButtonWidth(panelWidth - 32);

                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: panelWidth),
                  child: HydraCamSurface(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SessionInfoWidget(
                          sessionDisplay: _sessionDisplay(),
                          compact: true,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _connectedDevicesWidget(),
                            const HydraCamStatusChip(
                              status: HydraCamStatusTone.neutral,
                              icon: Icons.event_busy_outlined,
                              label: "No active session",
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        CourtSelectionWidget(
                          groupedCourts: sortedGroupedCourts,
                          onCourtSelected: (selection) {
                            _controller.selectCourt(
                              sportsCenterName: selection?.sportsCenterName,
                              courtName: selection?.courtName,
                              courtGuid: selection?.courtGuid,
                            );
                            _refreshGeneratedSessionName();
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const ValueKey("activityPresetDropdown"),
                          initialValue: selectedActivityPreset,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Activity",
                            prefixIcon: Icon(Icons.sports_tennis_outlined),
                          ),
                          items: sessionNamingService.activityPresets
                              .map(
                                (preset) => DropdownMenuItem<String>(
                                  value: preset,
                                  child: Text(
                                    preset,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (preset) {
                            if (preset == null) {
                              return;
                            }
                            _controller.selectActivityPreset(preset);
                            _refreshGeneratedSessionName();
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey("sessionNameField"),
                          controller: sessionNameController,
                          decoration: InputDecoration(
                            labelText: "Session name",
                            prefixIcon:
                                const Icon(Icons.edit_calendar_outlined),
                            suffixIcon: IconButton(
                              key: const ValueKey(
                                  "resetGeneratedSessionNameButton"),
                              icon: const Icon(Icons.auto_fix_high_outlined),
                              tooltip: "Reset generated session name",
                              onPressed: () => setState(() {
                                _refreshGeneratedSessionName(force: true);
                              }),
                            ),
                          ),
                          onChanged: (_) {
                            sessionNameEditedManually = true;
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _actionButton(
                              width: buttonWidth,
                              icon: isProcessingStartSession
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: AppTheme.inverseText,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow_outlined),
                              label: isProcessingStartSession
                                  ? "Starting session"
                                  : "Start Session",
                              onPressed: isProcessingStartSession
                                  ? null
                                  : () => unawaited(
                                      _controller.startOrEndSession()),
                            ),
                            _actionButton(
                              width: buttonWidth,
                              icon: const Icon(Icons.folder_open_outlined),
                              label: "Load Existing Session",
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SportsCentersScreen(),
                                ),
                              ),
                            ),
                            _actionButton(
                              width: buttonWidth,
                              icon: const Icon(Icons.history_outlined),
                              label: "Review Stored Media",
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const PreviousSessionsScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Build the UI when a session is active
  Widget _buildSessionUI() {
    final String? sessionGuid = _controller.sessionGuid;

    // Buttons and connected devices widget
    final Widget controls = LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final buttonWidth = _actionButtonWidth(maxWidth - 24);

        return HydraCamSurface(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SessionInfoWidget(
                sessionDisplay: _sessionDisplay(),
                compact: true,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _connectedDevicesWidget(),
                  HydraCamStatusChip(
                    status: _recordingActive
                        ? HydraCamStatusTone.recording
                        : HydraCamStatusTone.active,
                    icon: _recordingActive
                        ? Icons.fiber_manual_record
                        : Icons.event_available_outlined,
                    label: _recordingActive ? "Recording" : "Session active",
                  ),
                ],
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _actionButton(
                    width: buttonWidth,
                    icon: isProcessingTakePhoto
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppTheme.inverseText,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    label:
                        isProcessingTakePhoto ? "Taking photo" : "Take Photo",
                    onPressed: sessionGuid != null && !isProcessingTakePhoto
                        ? _handleTakePhotoButton
                        : null,
                  ),
                  _actionButton(
                    width: buttonWidth,
                    icon: Icon(
                      _recordingActive
                          ? Icons.stop_circle_outlined
                          : Icons.videocam_outlined,
                    ),
                    label:
                        _recordingActive ? "Stop Recording" : "Start Recording",
                    onPressed: sessionGuid != null
                        ? _handleToggleRecordingButton
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _recordingActive ? AppTheme.danger : AppTheme.accent,
                      foregroundColor: _recordingActive
                          ? AppTheme.inverseText
                          : AppTheme.textOnAccent,
                    ),
                  ),
                  _actionButton(
                    width: buttonWidth,
                    icon: isProcessingEndSession
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppTheme.inverseText,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.stop_outlined),
                    label: isProcessingEndSession
                        ? "Ending session"
                        : "End Session",
                    onPressed: isProcessingEndSession || sessionGuid == null
                        ? null
                        : () => unawaited(_controller.endCurrentSession()),
                    style: AppTheme.dangerButtonStyle(),
                  ),
                  _actionButton(
                    width: buttonWidth,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: "Start Uploads",
                    onPressed: sessionGuid != null
                        ? () => unawaited(_controller.startAllUploads())
                        : null,
                  ),
                  SizedBox(
                    width: buttonWidth,
                    height: _masterActionButtonHeight,
                    child: AddGalleryMediaButton(enabled: !_recordingActive),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    return PopScope(
      canPop: false, // We handle back navigation ourselves
      onPopInvokedWithResult: (didPop, result) {
        if (_recordingActive) return; // Ignore back while recording

        // Handle the back button press
        _controller.stopServerAndAnnouncer();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        );
      },
      child: Scaffold(
        appBar: HydraCamAppBar(
          title: "HydraCam - Master Control",
          onBack: () {
            _controller.stopServerAndAnnouncer();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const RoleSelectionScreen()),
            );
          },
        ),
        body: Center(
          child: sessionActive ? _buildSessionUI() : _buildInitialUI(),
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
        if (!mounted) {
          return;
        }
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
    SessionManager.instance.removeListener(_onSessionChanged);
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
