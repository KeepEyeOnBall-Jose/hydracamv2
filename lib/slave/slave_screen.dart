import "dart:async";
import "package:camera/camera.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/material.dart";
import "../app_theme.dart";
import "../constants.dart" as constants;
import "../screens/camera_setup_preview_screen.dart";
import "../screens/role_selection_screen.dart";
import "../screens/uploader_info_screen.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../models/sync_metadata.dart";
import "../services/alert_utils.dart";
import "../services/device_service.dart";
import "../services/settings_service.dart";
import "../services/time_sync_service.dart";
import "slave_screen_controller.dart";
import "../widgets/add_gallery_media_button.dart";
import "../widgets/animated_countdown_timer.dart";
import "../widgets/camera_preview_widget.dart";
import "../widgets/hydra_cam_app_bar.dart";
import "../widgets/hydracam_surface.dart";
import "../widgets/media_list_widget.dart";
import "../widgets/session_info_widget.dart";
import "../services/session_manager.dart";
import "../master/master_screen.dart";

class SlaveScreen extends StatefulWidget {
  // Mode that controls if we entered here manually or on app init.
  // If is auto mode, after some time without finding master will move automatically to master screen
  final bool isAutoMode;
  final String? preferredMasterIp;
  final bool forceSlaveMode;
  final NetworkReadinessLoader? networkReadinessLoader;
  final SlaveConnectionClientFactory? slaveClientFactory;
  final MasterDiscoveryFactory? masterDiscoveryFactory;
  final Stream<List<ConnectivityResult>>? connectivityChanges;
  final DateTime Function()? syncStatusNow;
  final SlaveScreenController? controller;

  const SlaveScreen({
    super.key,
    this.isAutoMode = false,
    this.preferredMasterIp,
    this.forceSlaveMode = false,
    @visibleForTesting this.networkReadinessLoader,
    @visibleForTesting this.slaveClientFactory,
    @visibleForTesting this.masterDiscoveryFactory,
    @visibleForTesting this.connectivityChanges,
    @visibleForTesting this.syncStatusNow,
    @visibleForTesting this.controller,
  }); // Default is manual mode

  @override
  SlaveScreenState createState() => SlaveScreenState();
}

class SlaveScreenState extends State<SlaveScreen> {
  static const Duration _identifyFrameDuration = Duration(seconds: 2);

  late final SlaveScreenController _controller;
  late final bool _ownsController;

  Timer? dimTimer; // Timer for screen dimming
  Timer? _identifyFrameTimer;
  Timer? _syncStatusRefreshTimer;
  int dimTime = 10; // Number of seconds before turning screen black
  bool isScreenDimmed = false; // To control the dimmed screen state
  bool _isIdentifyFrameVisible = false;

  @override
  void initState() {
    super.initState();

    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        SlaveScreenController(
          isAutoMode: widget.isAutoMode,
          preferredMasterIp: widget.preferredMasterIp,
          forceSlaveMode: widget.forceSlaveMode,
          networkReadinessLoader: widget.networkReadinessLoader,
          slaveClientFactory: widget.slaveClientFactory,
          masterDiscoveryFactory: widget.masterDiscoveryFactory,
          connectivityChanges: widget.connectivityChanges,
        );

    // Wire presentation hooks that require BuildContext / screen-local UI state.
    _controller.onScheduledCommand = _showCountdownTimer;
    _controller.onPhotoTaken = _handlePhotoTaken;
    _controller.onRecordingStarted = _handleRecordingStarted;
    _controller.onRecordingStopped = _handleRecordingStopped;
    _controller.onIdentifyAcknowledged = _handleIdentifyAcknowledged;
    _controller.onAutoPromote = _transitionToMasterScreen;
    _controller.addListener(_onControllerChanged);

    if (_ownsController) {
      _controller.start();
    }

    _syncStatusRefreshTimer = Timer.periodic(
      const Duration(seconds: constants.timeSyncStatusRefreshSeconds),
      (_) {
        if (mounted && TimeSyncService.instance.latest.value != null) {
          setState(() {});
        }
      },
    );
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handlePhotoTaken(String path) async {
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
        autoCloseSeconds: constants.secondsToClosePhoto);
  }

  void _handleIdentifyAcknowledged() {
    if (!mounted) {
      return;
    }
    setState(() {
      isScreenDimmed = false;
      _isIdentifyFrameVisible = true;
    });

    _identifyFrameTimer?.cancel();
    _identifyFrameTimer = Timer(_identifyFrameDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _isIdentifyFrameVisible = false;
      });
    });
  }

  void _handleRecordingStarted() {
    if (mounted) {
      unawaited(_startDimTimer());
    }
  }

  void _handleRecordingStopped() {
    if (mounted) {
      setState(() {
        isScreenDimmed = false;
      });
      dimTimer?.cancel();
    }
  }

  Future<void> _startDimTimer() async {
    dimTimer?.cancel();
    if (!await _getAutoOffSetting() || !mounted) {
      return;
    }
    dimTimer = Timer(Duration(seconds: dimTime), () {
      if (mounted && _controller.isRecording) {
        setState(() {
          isScreenDimmed = true;
        });
      }
    });
  }

  Future<void> _resetDimTimer() async {
    if (mounted) {
      setState(() {
        isScreenDimmed = false;
      });
      await _startDimTimer();
    }
  }

  Future<bool> _getAutoOffSetting() async {
    return await SettingsService.getScreenAutoOff();
  }

  void _transitionToMasterScreen() {
    if (!mounted) {
      return;
    }
    // The controller has already torn down slave-side activity; cancel the
    // screen-local identify overlay timer before navigating.
    _identifyFrameTimer?.cancel();
    _identifyFrameTimer = null;

    // Move to master screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MasterScreen()),
    );
  }

  void _onBack() {
    // Stop any activity related to Slave, then return to role selection.
    _identifyFrameTimer?.cancel();
    _identifyFrameTimer = null;
    _controller.cleanUpSlaveMode();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
    );
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
    dimTimer?.cancel();
    _identifyFrameTimer?.cancel();
    _syncStatusRefreshTimer?.cancel();

    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }

    super.dispose();
  }

  /// Compact clock-sync status indicator driven by the latest calibration.
  Widget _buildSyncStatusChip({bool compact = false}) {
    return ValueListenableBuilder<TimeSyncResult?>(
      valueListenable: TimeSyncService.instance.latest,
      builder: (context, result, child) {
        final HydraCamStatusTone tone;
        final IconData icon;
        final String label;
        if (result == null) {
          tone = HydraCamStatusTone.neutral;
          icon = Icons.sync_outlined;
          label = compact ? "Clock: syncing" : "Clock sync: calibrating…";
        } else {
          final now = (widget.syncStatusNow ?? DateTime.now)().toUtc();
          final confidence = result.confidenceAt(now);
          final ageSeconds = result.ageAt(now).inSeconds;
          tone = switch (confidence) {
            TimeSyncConfidence.green => HydraCamStatusTone.active,
            TimeSyncConfidence.yellow => HydraCamStatusTone.warning,
            TimeSyncConfidence.red => HydraCamStatusTone.danger,
          };
          icon = switch (confidence) {
            TimeSyncConfidence.green => Icons.sync_outlined,
            TimeSyncConfidence.yellow => Icons.sync_problem_outlined,
            TimeSyncConfidence.red => Icons.sync_disabled_outlined,
          };
          label = compact
              ? "Clock: ±${result.uncertainty.inMilliseconds} ms · "
                  "${ageSeconds}s"
              : "Clock sync: ±${result.uncertainty.inMilliseconds} ms · "
                  "RTT ${result.minRoundTrip.inMilliseconds} ms · "
                  "${result.sampleCount} samples · age ${ageSeconds}s";
        }
        return HydraCamStatusChip(
          status: tone,
          icon: icon,
          label: label,
        );
      },
    );
  }

  Widget _buildStatusMessage() {
    final statusMessage = _controller.statusMessage;
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

  Widget _buildCameraPreviewArea() {
    final controller = _controller.cameraController;
    final isConnected = _controller.isConnected;
    final isRecording = _controller.isRecording;

    if (controller == null) {
      if (isConnected && !isRecording) {
        return const CameraSetupPreviewPanel(
          title: "Prepare Camera",
        );
      }
      return Stack(
        children: [
          _buildStatusMessage(),
          if (isRecording) _recordingControls(),
        ],
      );
    }

    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, cameraValue, child) {
        if (isConnected && !isRecording) {
          return CameraSetupPreviewPanel(
            title: "Prepare Camera",
            preview: cameraValue.isInitialized
                ? CameraPreviewWidget(controller: controller)
                : null,
          );
        }

        return Stack(
          children: [
            if (isRecording && cameraValue.isInitialized)
              Positioned.fill(
                child: CameraPreviewWidget(controller: controller),
              )
            else
              _buildStatusMessage(),
            if (isRecording) _recordingControls(),
          ],
        );
      },
    );
  }

  Widget _recordingControls() {
    final isStoppingRecording = _controller.isStoppingRecording;
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HydraCamStatusChip(
              status: HydraCamStatusTone.recording,
              icon: Icons.fiber_manual_record,
              label: "Recording...",
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: "Stop recording safely",
              child: ElevatedButton.icon(
                key: const ValueKey("slaveStopRecordingButton"),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(isStoppingRecording ? "Stopping..." : "Stop"),
                style: AppTheme.dangerButtonStyle(),
                onPressed: isStoppingRecording
                    ? null
                    : _controller.stopRecordingSafely,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identifyFrameOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.accent, width: 10),
            color: AppTheme.previewOverlay,
          ),
          child: const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.appChrome,
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  "Identifying this slave",
                  style: TextStyle(
                    color: AppTheme.inverseText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploaderInfoAction() {
    return IconButton(
      tooltip: "Uploader Info",
      icon: const Icon(Icons.cloud_upload_outlined),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UploaderInfoScreen()),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final shortestSide = mediaQuery.size.shortestSide;
    final longestSide = mediaQuery.size.longestSide;
    final isCompactLandscapePhone =
        !isPortrait && shortestSide <= 620 && longestSide <= 900;
    final statusPanelMargin = isCompactLandscapePhone
        ? const EdgeInsets.fromLTRB(4, 4, 4, 6)
        : const EdgeInsets.all(8);
    final statusPanelPadding = isCompactLandscapePhone
        ? const EdgeInsets.all(8)
        : const EdgeInsets.all(12);
    final previewGap = isCompactLandscapePhone ? 6.0 : 10.0;
    final isConnected = _controller.isConnected;
    final isRecording = _controller.isRecording;

    // Media list widget with placeholder enabled
    final Widget mediaList = MediaListWidget(
      photos: _controller.photos,
      videos: _controller.videos,
      onPhotoTap: _showPhotoDialog,
      onVideoTap: _showVideoDialog,
      showPlaceholder: true, // Enable placeholder
    );

    // Controls and camera preview widget
    final Widget controlsAndPreview = Column(
      children: [
        HydraCamSurface(
          tone: HydraCamSurfaceTone.muted,
          margin: statusPanelMargin,
          padding: statusPanelPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SessionInfoWidget(
                sessionDisplay:
                    SessionManager.instance.currentSession?.displayTitle ??
                        "No active session",
                compact: isCompactLandscapePhone,
                showDiagnostics: !isCompactLandscapePhone,
              ),
              SizedBox(height: isCompactLandscapePhone ? 6 : 8),
              Wrap(
                spacing: isCompactLandscapePhone ? 6 : 8,
                runSpacing: isCompactLandscapePhone ? 6 : 8,
                children: [
                  HydraCamStatusChip(
                    status: isConnected
                        ? HydraCamStatusTone.active
                        : HydraCamStatusTone.neutral,
                    icon: isConnected
                        ? Icons.link_outlined
                        : Icons.link_off_outlined,
                    label: isConnected ? "Master connected" : "Searching",
                  ),
                  _buildSyncStatusChip(compact: isCompactLandscapePhone),
                ],
              ),
            ],
          ),
        ),
        if (!isCompactLandscapePhone) ...[
          AddGalleryMediaButton(enabled: !isRecording),
          SizedBox(height: previewGap),
        ],
        Expanded(
          child: _buildCameraPreviewArea(),
        ),
      ],
    );

    // Adjust layout based on orientation
    if (isPortrait) {
      // Vertical layout: controls and media list stacked
      return GestureDetector(
          onTap: () => unawaited(
                _resetDimTimer(),
              ), // Reset dimming on user interaction
          child: Stack(
            children: [
              Scaffold(
                appBar: HydraCamAppBar(
                  title: "HydraCam - Slave Device",
                  onBack: _onBack,
                  additionalActions: [_buildUploaderInfoAction()],
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
                  onTap: () => unawaited(
                    _resetDimTimer(),
                  ), // Wake up the screen
                  child: Container(
                    color: AppTheme.cameraCanvas,
                    child: const Center(
                      child: Text(
                        "Screen Off - Tap to wake",
                        style: TextStyle(
                          color: AppTheme.inverseText,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isIdentifyFrameVisible) _identifyFrameOverlay(),
            ],
          ));
    } else {
      // Horizontal layout: controls on the left, media list on the right
      return GestureDetector(
        onTap: () => unawaited(_resetDimTimer()),
        child: Stack(
          children: [
            Scaffold(
              appBar: HydraCamAppBar(
                title: "HydraCam - Slave Device",
                onBack: _onBack,
                additionalActions: [_buildUploaderInfoAction()],
              ),
              body: Row(
                children: [
                  Expanded(
                    flex: isCompactLandscapePhone ? 3 : 1,
                    child: Padding(
                      padding: EdgeInsets.all(
                        isCompactLandscapePhone ? 4.0 : 8.0,
                      ),
                      child: controlsAndPreview,
                    ),
                  ),
                  Expanded(
                    flex: isCompactLandscapePhone ? 2 : 1,
                    child: Padding(
                      padding: EdgeInsets.all(
                        isCompactLandscapePhone ? 4.0 : 8.0,
                      ),
                      child: isCompactLandscapePhone
                          ? Column(
                              children: [
                                AddGalleryMediaButton(enabled: !isRecording),
                                SizedBox(height: previewGap),
                                Expanded(child: mediaList),
                              ],
                            )
                          : mediaList,
                    ),
                  ),
                ],
              ),
            ),
            if (isScreenDimmed)
              GestureDetector(
                onTap: () => unawaited(
                  _resetDimTimer(),
                ), // Wake up the screen
                child: Container(
                  color: AppTheme.cameraCanvas,
                  child: const Center(
                    child: Text(
                      "Screen Off - Tap to wake",
                      style: TextStyle(
                        color: AppTheme.inverseText,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            if (_isIdentifyFrameVisible) _identifyFrameOverlay(),
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
        autoCloseSeconds: constants.secondsToClosePhoto);
  }

  void _showVideoDialog(CapturedVideo video) {
    AlertUtils.showMediaDialog(
      context: context,
      media: video,
      isAutoCloseEnabled: false, // Auto-close is disabled for slave screens
    );
  }
}
