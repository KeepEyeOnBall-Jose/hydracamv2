import "dart:async";

import "package:flutter/foundation.dart";

import "../automation/automation_bridge.dart";
import "../automation/automation_config.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../models/sync_metadata.dart";
import "../services/camera_service.dart";
import "../services/camera_service_singleton.dart";
import "../services/debug_session_policy.dart";
import "../services/debug_session_registry.dart";
import "../services/device_service.dart";
import "../services/hydracam_api_service.dart";
import "../services/log_service.dart";
import "../services/session_manager.dart";
import "../services/session_naming_service.dart";
import "../services/settings_service.dart";
import "../services/storage_service.dart";
import "../services/uploader_service.dart";
import "../services/user_service.dart";
import "connected_client_automation_payload.dart";
import "master_announcer.dart";
import "master_server.dart";

/// Presentation delegate that shows a transient message (snackbar) to the user.
typedef ShowMessageDelegate = void Function(String message,
    {Duration? duration});

/// Presentation delegate that shows the scheduling countdown dialog.
typedef ShowCountdownDelegate = void Function(int durationMs);

/// Presentation delegate that returns the user's confirmation from a dialog.
typedef ConfirmDelegate = Future<bool> Function();

/// Presentation delegate that pushes the master camera setup preview and
/// returns whether the user confirmed the recording start.
typedef ShowCameraSetupPreviewDelegate = Future<bool> Function();

/// Presentation delegate that pushes the master video recording preview screen.
typedef ShowMasterVideoPreviewDelegate = Future<void> Function();

/// Presentation delegate that shows a captured photo dialog.
typedef ShowPhotoDialogDelegate = void Function(
  CapturedPhoto photo, {
  bool autoClose,
});

/// Presentation delegate that shows a captured video dialog.
typedef ShowVideoDialogDelegate = void Function(
  CapturedVideo video, {
  bool autoClose,
});

/// Owns the non-presentation logic for [MasterScreen]: the [MasterServer]
/// lifecycle, session orchestration, capture orchestration, networking state
/// and automation wiring.
///
/// The screen keeps ephemeral UI state (text controllers, dialogs, navigation)
/// and supplies the presentation delegates below so this controller stays free
/// of `BuildContext`.
class MasterScreenController extends ChangeNotifier {
  MasterScreenController({
    MasterServer? masterServer,
    MasterAnnouncer? announcer,
    HydraCamApiService? apiService,
    DebugSessionPolicy? debugSessionPolicy,
    SessionManager? sessionManager,
  })  : _server = masterServer ?? MasterServer(CameraServiceSingleton.instance),
        _announcer = announcer ?? MasterAnnouncer(),
        _apiService = apiService ?? HydraCamApiService(),
        _debugSessionPolicy = debugSessionPolicy ?? DebugSessionPolicy(),
        _sessionManager = sessionManager ?? SessionManager.instance,
        _selectedActivityPreset = sessionNamingService.defaultActivityPreset;

  final MasterServer _server;
  final MasterAnnouncer _announcer;
  final HydraCamApiService _apiService;
  final DebugSessionPolicy _debugSessionPolicy;
  final SessionManager _sessionManager;
  final Map<String, AutomationHandler> _automationHandlers = {};

  // Presentation delegates supplied by the screen State. All are optional so
  // the controller can run headless (tests, automation) without any UI.
  ShowMessageDelegate? showMessage;
  ShowCountdownDelegate? showCountdownDialog;
  ConfirmDelegate? confirmStartWithoutCourt;
  ConfirmDelegate? confirmEndSession;
  ShowCameraSetupPreviewDelegate? showCameraSetupPreview;
  ShowMasterVideoPreviewDelegate? showMasterVideoPreview;
  ShowPhotoDialogDelegate? showPhotoDialog;
  ShowVideoDialogDelegate? showVideoDialog;

  /// Supplies the live custom session-name text from the screen's text field.
  String Function()? currentCustomSessionName;

  int _connectedClients = 0;
  bool _isRecording = false;
  bool _isRecordingTransitioning = false;
  bool _isProcessingEndSession = false;
  bool _isProcessingStartSession = false;
  bool _isProcessingTakePhoto = false;

  String _selectedActivityPreset;
  String? _selectedSportsCenterName;
  String? _selectedCourtName;
  String? _selectedCourtGuid;

  bool _disposed = false;
  bool get _alive => !_disposed;

  // ---------------------------------------------------------------------------
  // Read-only getters
  // ---------------------------------------------------------------------------

  MasterServer get server => _server;
  MasterAnnouncer get announcer => _announcer;
  HydraCamApiService get apiService => _apiService;
  DebugSessionPolicy get debugSessionPolicy => _debugSessionPolicy;
  SessionManager get sessionManager => _sessionManager;
  CameraService get cameraService => _server.cameraService;
  DateTime? get serverStartedAt => _server.serverStartedAt;

  int get connectedClients => _connectedClients;
  bool get isRecording => _isRecording;
  bool get isProcessingEndSession => _isProcessingEndSession;
  bool get isProcessingStartSession => _isProcessingStartSession;
  bool get isProcessingTakePhoto => _isProcessingTakePhoto;

  bool get recordingActive =>
      _isRecording ||
      _server.cameraService.isRecording ||
      (_server.cameraService.controller?.value.isRecordingVideo ?? false);

  bool get sessionActive => _sessionManager.isSessionActive;
  String? get sessionGuid => _sessionManager.sessionGuid;

  List<CapturedPhoto> get photos =>
      _sessionManager.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos =>
      _sessionManager.currentSession?.capturedVideos ?? [];

  String get selectedActivityPreset => _selectedActivityPreset;
  String? get selectedSportsCenterName => _selectedSportsCenterName;
  String? get selectedCourtName => _selectedCourtName;
  String? get selectedCourtGuid => _selectedCourtGuid;

  List<String> getConnectedDeviceIds() => _server.getConnectedDeviceIds();
  List<ConnectedDeviceInfo> getConnectedDeviceInfos() =>
      _server.getConnectedDeviceInfos();

  String get sessionDisplay {
    if (!sessionActive) {
      return "No active session";
    }
    return _sessionManager.currentSession?.displayTitle ?? "Active session";
  }

  String get generatedSessionName {
    return sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: _selectedActivityPreset,
        sportsCenterName: _selectedSportsCenterName,
        courtName: _selectedCourtName,
        players: const [],
        startTime: DateTime.now(),
      ),
    );
  }

  String sessionDisplayNameForCreation({String? overrideDisplayName}) {
    final override =
        sessionNamingService.sanitizeCustomName(overrideDisplayName ?? "");
    if (override.isNotEmpty) {
      return override;
    }

    final custom = sessionNamingService
        .sanitizeCustomName(currentCustomSessionName?.call() ?? "");
    if (custom.isNotEmpty) {
      return custom;
    }

    return generatedSessionName;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Wires the server callbacks, starts the server and announcer, and registers
  /// automation handlers. Mirrors the screen's previous `initState` behavior.
  void initialize() {
    _announcer.startBroadcasting();

    _server.onClientCountChange = (count) {
      if (_disposed) {
        return;
      }
      _connectedClients = count;
      notifyListeners();
    };
    _server.onMediaReceived = (media) {
      _safeNotify();
    };
    // Notify disconnection through the presentation delegate.
    _server.onClientRemoved = (deviceId, inactivityThreshold) {
      showMessage?.call(
        "Client $deviceId disconnected after $inactivityThreshold seconds of inactivity.",
      );
    };
    unawaited(_server.startServer());

    if (automationEnabled) {
      _registerAutomationHandlers();
      // Register callback for automation bridge to get recording state
      AutomationBridge.instance.getRecordingState = () => recordingActive;
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
      // Nullify callbacks to prevent notifications after dispose.
      _server.onClientCountChange = null;
      _server.onMediaReceived = null;
      _server.onClientRemoved = null;

      // Stop server and announcer
      _server.stopServer();
      _announcer.stopBroadcasting();
      // Controller disposal is resource cleanup only. End the capture session
      // via endCurrentSession() when the user or automation requests it.
    } catch (e) {
      LogService.instance.registerLog("Error during dispose: $e");
    }
    _disposed = true;
    super.dispose();
  }

  /// Tears down the server and announcer without disposing the controller.
  /// Used by the screen's back navigation.
  void stopServerAndAnnouncer() {
    _server.stopServer();
    _announcer.stopBroadcasting();
  }

  // ---------------------------------------------------------------------------
  // Selection intents
  // ---------------------------------------------------------------------------

  void selectCourt({
    String? sportsCenterName,
    String? courtName,
    String? courtGuid,
  }) {
    _selectedSportsCenterName = sportsCenterName;
    _selectedCourtName = courtName;
    _selectedCourtGuid = courtGuid;
    _safeNotify();
  }

  void selectActivityPreset(String preset) {
    _selectedActivityPreset = preset;
    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // Session intents
  // ---------------------------------------------------------------------------

  Future<void> startOrEndSession() async {
    if (sessionActive) {
      await endCurrentSession();
    } else {
      final shouldStart = _selectedCourtGuid != null ||
          (await confirmStartWithoutCourt?.call() ?? false);
      if (!shouldStart) {
        return;
      }
      await createSession(skipCourtSelectionWarning: true);
    }
  }

  Future<void> startAllUploads() async {
    _server.sendCommand("startUploadingAll");
    await UploaderService().startUploadingManually();
  }

  Future<void> createSession({
    bool suppressSnackbars = false,
    bool skipCourtSelectionWarning = false,
    String? overrideCourtGuid,
    String? overrideSessionId,
    String? overrideDisplayName,
  }) async {
    if (_isProcessingStartSession) return;

    _isProcessingStartSession = true;
    _safeNotify();

    try {
      final sessionId =
          overrideSessionId ?? _debugSessionPolicy.defaultSessionId();
      final debugSession =
          overrideSessionId == null && _debugSessionPolicy.debugBuild;
      final displayName = sessionDisplayNameForCreation(
        overrideDisplayName: overrideDisplayName,
      );

      if (!skipCourtSelectionWarning && _selectedCourtGuid == null) {
        showMessage?.call(
          "No court selected. Proceeding without a court.",
          duration: const Duration(seconds: 3),
        );
      }

      final String? userGuid = UserService().guid;
      final backendSession = await _apiService.createSession(
        sessionId,
        courtGuid: overrideCourtGuid ?? _selectedCourtGuid,
        userGuid: userGuid,
      );

      LogService.instance
          .registerLog("Response to create session: $backendSession");

      if (!_alive) return;

      if (backendSession != null) {
        final String sessionGuid = backendSession.guid;
        _sessionManager.startCreatedSession(
          backendSession,
          deviceType: "Master",
          debugSession: debugSession,
          displayName: displayName,
        );
        if (debugSession) {
          await DebugSessionRegistry().record(
            DebugSessionRef(
              sessionGuid: backendSession.guid,
              sessionId: backendSession.sessionId,
              serviceNumericId: backendSession.numericId,
            ),
          );
          if (!_alive) return;
        }
        _server.startNewSession(sessionGuid, displayName: displayName);

        LogService.instance
            .registerLog("Session created with GUID: $sessionGuid");

        _safeNotify();
        if (!suppressSnackbars) {
          showMessage?.call("Session created: $displayName");
        }
      } else {
        if (!suppressSnackbars) {
          showMessage?.call("Failed to create session");
        }
      }
    } finally {
      _isProcessingStartSession = false;
      _safeNotify();
    }
  }

  Future<void> endCurrentSession({
    bool requireConfirmation = true,
    bool suppressSnackbars = false,
  }) async {
    if (_isProcessingEndSession) return;

    // If recording is active, stop and save video first
    if (recordingActive) {
      LogService.instance
          .registerLog("Stopping active recording before ending session");
      try {
        if (await SettingsService.getMasterShouldRecord()) {
          await stopMasterRecordingVideo();
        } else {
          _setRecording(false);
        }
      } catch (e) {
        LogService.instance
            .registerLog("Error stopping recording before session end: $e");
      }
    }

    if (!_alive) return;
    _isProcessingEndSession = true;
    _safeNotify();

    try {
      bool proceed = true;
      if (requireConfirmation) {
        proceed = await confirmEndSession?.call() ?? false;
      }

      if (!proceed) {
        return;
      }

      if (_sessionManager.currentSession != null) {
        final bool success =
            await _apiService.endSession(_sessionManager.sessionGuid!);

        if (!_alive) return;

        if (success) {
          await _server.endCurrentSession();
          if (!_alive) return;
          _safeNotify();
          if (!suppressSnackbars) {
            showMessage?.call("Capture session ended");
          }
        } else {
          if (!suppressSnackbars) {
            showMessage?.call("Failed to end session on the server");
          }
        }
      }
    } finally {
      _isProcessingEndSession = false;
      _safeNotify();
    }
  }

  // ---------------------------------------------------------------------------
  // Capture / recording intents
  // ---------------------------------------------------------------------------

  Future<void> toggleRecording({
    bool showCountdown = true,
    bool suppressSnackbars = false,
    bool showPreview = true,
  }) async {
    if (StorageService.instance.isRecordingBlocked) {
      if (!suppressSnackbars) {
        showMessage?.call("Cannot start recording: Storage is critically low.");
      }
      LogService.instance
          .registerLog("Recording toggle blocked due to critical storage.");
      return;
    }

    if (_server.cameraService.recordingInterrupted.value) {
      if (!suppressSnackbars) {
        showMessage?.call("Recording already interrupted due to low storage.");
      }
      return;
    }

    LogService.instance.registerLog(
        "PRESSED TOGGLE RECORDING. IS RECORDING = $recordingActive");

    final bool shouldStartRecording = !recordingActive;
    final bool shouldMasterRecord =
        await SettingsService.getMasterShouldRecord();
    if (shouldStartRecording && shouldMasterRecord && showPreview) {
      final didConfirmSetup = await showCameraSetupPreview?.call() ?? false;
      if (!didConfirmSetup) {
        LogService.instance
            .registerLog("Master recording setup preview was cancelled.");
        return;
      }
    }

    final timerDuration = await SettingsService.getTimerDuration();
    final DateTime scheduledTime =
        DateTime.now().add(Duration(seconds: timerDuration));
    final String command =
        recordingActive ? "stopRecordingVideo" : "startRecordingVideo";

    if (!_alive) return;
    if (showCountdown) {
      showCountdownDialog
          ?.call(scheduledTime.difference(DateTime.now()).inMilliseconds);
    }

    _server.scheduleCommand(command, scheduledTime);
    await Future.delayed(scheduledTime.difference(DateTime.now()));

    if (!_alive) return;

    try {
      if (recordingActive) {
        if (shouldMasterRecord) {
          await stopMasterRecordingVideo();
        } else {
          _setRecording(false);
        }
      } else {
        if (shouldMasterRecord) {
          final didStart =
              await startMasterRecordingVideo(showPreview: showPreview);
          if (!didStart) {
            LogService.instance.registerLog(
                "Recording toggle did not start local master recording.");
          }
        } else {
          _setRecording(true);
        }
      }
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Recording toggle failed: $error\n$stackTrace");
      if (!suppressSnackbars) {
        showMessage?.call("Recording command failed: ${_describeError(error)}");
      }
    }

    LogService.instance.registerLog(
        "Command '$command' finished executing by master at ${DateTime.now()}");
  }

  Future<void> ensureRecordingState({required bool shouldRecord}) async {
    // Wait for any ongoing state transitions
    int waitCount = 0;
    while (_isRecordingTransitioning && waitCount < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }

    if (shouldRecord == recordingActive) {
      return;
    }

    _isRecordingTransitioning = true;
    try {
      await toggleRecording(
        showCountdown: false,
        suppressSnackbars: true,
        showPreview: false,
      );

      // Wait for recording state to actually change (with timeout)
      waitCount = 0;
      while (recordingActive != shouldRecord && waitCount < 300) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      if (recordingActive != shouldRecord) {
        LogService.instance.registerLog(
            "Warning: Recording state did not change to $shouldRecord after 30s");
      }
    } finally {
      _isRecordingTransitioning = false;
    }
  }

  Future<bool> startMasterRecordingVideo({bool showPreview = true}) async {
    LogService.instance.registerLog("Will record from master and show preview");
    try {
      await _server.cameraService.startRecordingVideo();
      if (!_alive) {
        return false;
      }
      _setRecording(true);
      if (showPreview) {
        final preview = showMasterVideoPreview?.call();
        if (preview != null) {
          unawaited(preview);
        }
      }
      return true;
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Master recording start failed: $error\n$stackTrace");
      if (_alive) {
        _setRecording(false);
        showMessage
            ?.call("Could not start recording: ${_describeError(error)}");
      }
      return false;
    }
  }

  Future<CapturedVideo> stopMasterRecordingVideo() async {
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
      captureContext: _server.cameraService.recordingCaptureContext,
      // The master defines the shared clock, so its captures are the anchor.
      syncMetadata: SyncMetadata.masterAnchor(at: startRecordingDate),
    );

    await _sessionManager.addVideo(capturedVideo);

    if (_alive) {
      _setRecording(false);
    }

    // Return the captured video (dialog display is handled by the screen).
    return capturedVideo;
  }

  Future<void> executeTakePhoto({
    required bool showCountdown,
    bool suppressSnackbars = false,
  }) async {
    if (_isProcessingTakePhoto) return;

    _isProcessingTakePhoto = true;
    _safeNotify();

    try {
      final timerDuration = await SettingsService.getTimerDuration();
      final DateTime scheduledTime =
          DateTime.now().add(Duration(seconds: timerDuration));

      if (!_alive) return;
      if (showCountdown) {
        showCountdownDialog
            ?.call(scheduledTime.difference(DateTime.now()).inMilliseconds);
      }

      _server.scheduleCommand("takePhoto", scheduledTime);
      await Future.delayed(scheduledTime.difference(DateTime.now()));

      if (!_alive) return;

      final bool shouldMasterRecord =
          await SettingsService.getMasterShouldRecord();
      if (shouldMasterRecord) {
        try {
          final String photoPath = await _server.cameraService.takePhoto();
          final String deviceId = await DeviceIdService.getOrCreateDeviceId();

          final masterCaptureDate = DateTime.now();
          final capturedPhoto = CapturedPhoto(
            photoData: null,
            photoPath: photoPath,
            captureDate: masterCaptureDate,
            receivedDate: masterCaptureDate,
            slaveDeviceId: deviceId,
            captureContext: _server.cameraService.lastPhotoCaptureContext,
            // The master defines the shared clock, so its captures are the anchor.
            syncMetadata: SyncMetadata.masterAnchor(at: masterCaptureDate),
          );

          await _sessionManager.addPhoto(capturedPhoto);
          if (!_alive) return;
          _safeNotify();

          if (!suppressSnackbars) {
            showPhotoDialog?.call(capturedPhoto, autoClose: true);
          }
        } catch (error, stackTrace) {
          LogService.instance
              .registerLog("Master photo capture failed: $error\n$stackTrace");
          if (!suppressSnackbars) {
            showMessage?.call("Could not take photo: ${_describeError(error)}");
          }
        }
      }

      if (!_alive) return;
      if (!suppressSnackbars) {
        showMessage?.call("Photo scheduled for ${scheduledTime.toLocal()}");
      }

      LogService.instance
          .registerLog("Photo command executed by master at ${DateTime.now()}");
    } finally {
      _isProcessingTakePhoto = false;
      _safeNotify();
    }
  }

  // ---------------------------------------------------------------------------
  // Automation
  // ---------------------------------------------------------------------------

  void _registerAutomationHandlers() {
    if (!automationEnabled) {
      return;
    }

    final handlers = <String, AutomationHandler>{
      "start_session": (payload) async {
        await createSession(
          suppressSnackbars: true,
          skipCourtSelectionWarning: true,
          overrideCourtGuid: payload["courtGuid"] as String?,
          overrideSessionId: payload["sessionId"] as String?,
          overrideDisplayName: payload["displayName"] as String?,
        );
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "connected_clients": (payload) async {
        return {
          ...buildConnectedClientAutomationPayload(
            _server.getConnectedDeviceInfos(),
            serverStartedAt: _server.serverStartedAt,
            masterSessionGuid: _sessionManager.sessionGuid,
          ),
          "session": AutomationBridge.instance.buildSessionSnapshot(),
        };
      },
      "end_session": (payload) async {
        await endCurrentSession(
          requireConfirmation: false,
          suppressSnackbars: true,
        );
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "take_photo": (payload) async {
        await executeTakePhoto(
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
        await ensureRecordingState(shouldRecord: true);
        return AutomationBridge.instance.buildSessionSnapshot();
      },
      "stop_recording": (payload) async {
        await ensureRecordingState(shouldRecord: false);
        return AutomationBridge.instance.buildSessionSnapshot();
      },
    };

    handlers.forEach(AutomationBridge.instance.registerCommand);
    _automationHandlers.addAll(handlers);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _setRecording(bool value) {
    _isRecording = value;
    _safeNotify();
  }

  String _describeError(Object error) {
    return error.toString().replaceFirst("Exception: ", "");
  }

  void _safeNotify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }
}
