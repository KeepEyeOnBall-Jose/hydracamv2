import 'package:flutter/material.dart';
import 'package:hydracam/screens/previous_sessions_screen.dart';
import 'package:hydracam/screens/role_selection_screen.dart';
import 'package:hydracam/screens/sports_centers_screen.dart';
import 'package:video_player/video_player.dart'; // Add video_player dependency in pubspec.yaml
import '../constants.dart';
import '../globals.dart';
import '../master/master_announcer.dart';
import '../master/master_server.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'dart:io';
import '../services/alert_utils.dart';
import '../services/camera_service_singleton.dart';
import '../services/device_service.dart';
import '../services/hydracam_api_service.dart';
import '../services/log_service.dart';
import '../services/session_manager.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../widgets/Court_Selection_Widget.dart';
import '../widgets/add_gallery_media_button.dart';
import '../widgets/animated_countdown_timer.dart';
import '../widgets/hydra_cam_app_bar.dart';
import '../widgets/master_video_recording_screen.dart';
import '../widgets/media_list_widget.dart';
import '../widgets/session_info_widget.dart';

class MasterScreen extends StatefulWidget {
  const MasterScreen({super.key});

  @override
  _MasterScreenState createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final MasterServer _server = MasterServer(CameraServiceSingleton.instance); // Assign the singleton unique camera service TODO: SIMPLIFY DELETE CONSTRUCTOR
  final MasterAnnouncer _announcer = MasterAnnouncer(); // Broadcast announcer
  final HydraCamApiService _apiService = HydraCamApiService(); // API service instance

  int connectedClients = 0; // To display connected clients count
  bool isRecording = false;
  // String? sessionGuid; // Store the session GUID from the API (Now from Session Manager)
  bool get sessionActive => SessionManager.instance.isSessionActive; // TODO: Extract to session manager??
  String? selectedCourtName;  // Name of the selected Court
  String? selectedCourtGuid;  // GUID of the selected Court (TODO: To be improved)

  // Getters for SessionManager photos and videos
  List<CapturedPhoto> get photos => SessionManager.instance.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos => SessionManager.instance.currentSession?.capturedVideos ?? [];

  List<String> getConnectedDevices() {
    return _server.getConnectedDeviceIds();
  }

  // Processing indicators to prevent user from spamming buttons
  bool isProcessingEndSession = false;    // To block button "End Session"
  bool isProcessingStartSession = false;  // To block button "Start Session"
  bool isProcessingTakePhoto = false;     // To block button "Take Photo"


  @override
  void initState() {
    super.initState();
    _server.onClientCountChange = (count) {
      if (mounted){
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
    _announcer.startBroadcasting();
  }

  @override
  void dispose() {
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
      // End the session
      _endCurrentSession();
    } else {
      // Start a new session
      if (selectedCourtGuid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No court selected. Proceeding without a court."),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await _createSession();
    }
  }

  void _toggleRecording() async {

    if (StorageService.isRecordingBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot start recording: Storage is critically low.")),
      );
      LogService.instance.registerLog("Recording toggle blocked due to critical storage.");
      return;
    }

    if (_server.cameraService.recordingInterrupted.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Recording already interrupted due to low storage.")),
      );
      return;
    }

    LogService.instance.registerLog("PRESSED TOGGLE RECORDING. IS RECORDING = $isRecording");

    // Get timer duration
    final timerDuration = await SettingsService.getTimerDuration();
    final DateTime scheduledTime = DateTime.now().add(Duration(seconds: timerDuration));
    final String command = isRecording ? 'stopRecordingVideo' : 'startRecordingVideo';

    // Show countdown timer while waiting for the scheduled time
    if (context.mounted){
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AnimatedCountdownTimer(
          duration: scheduledTime.difference(DateTime.now()).inMilliseconds,
          onComplete: () => Navigator.of(context).pop(),
        ),
      );
    }

    // Send the scheduled command to slaves
    _server.scheduleCommand(command, scheduledTime);

    // Master also waits until the scheduled time before executing
    await Future.delayed(scheduledTime.difference(DateTime.now()));

    if (isRecording) {
      // Stop recording
      if (await SettingsService.getMasterShouldRecord()) {
        await _stopMasterRecordingVideo();
      } else {
        setState(() {
          isRecording = false;
        });
      }
    }
    else {
      // Start recording
      if (await SettingsService.getMasterShouldRecord()) {
        await _startMasterRecordingVideo();
      } else {
        setState(() {
          isRecording = true;
        });
      }
    }

    LogService.instance.registerLog("Command '$command' finished executing by master at ${DateTime.now()}");
  }


  Future<void> _startMasterRecordingVideo() async {
    LogService.instance.registerLog("Will record from master and show preview");
    await _server.cameraService.startRecordingVideo();
    // Show camera preview overlay
    _showMasterVideoPreview();
  }

  Future<CapturedVideo> _stopMasterRecordingVideo() async {

    // Send command to slaves before stopping from master
    _server.sendCommand('stopRecordingVideo');

    String videoPath = await _server.cameraService.stopRecordingVideo();

    // Get the device ID
    final String deviceId = await DeviceIdService.getOrCreateDeviceId();

    // Add video to current session
    final receivedDate = DateTime.now();
    final capturedVideo = CapturedVideo(
      videoData: null,
      videoPath: videoPath,
      slaveDeviceId: deviceId,
      startRecordingDate: _server.cameraService.videoStartRecordingDate!,
      endRecordingDate: _server.cameraService.videoEndRecordingDate!,
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
      bool autoplayEnabled = await SettingsService.getAutoplayVideoOnMaster();
      if (autoplayEnabled) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _showVideoDialog(capturedVideo, autoClose: true);
          }
        });
      }
    }
  }

  void _takeRealPhoto() async {

    if (isProcessingTakePhoto) return; // Prevent user from spamming

    setState(() {
      isProcessingTakePhoto = true; // Block the button
    });

    try{
      final timerDuration = await SettingsService.getTimerDuration();
      final DateTime scheduledTime = DateTime.now().add(Duration(seconds: timerDuration));

      // Show countdown timer while waiting for the scheduled time
      if (context.mounted){
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AnimatedCountdownTimer(
            duration: scheduledTime.difference(DateTime.now()).inMilliseconds,
            onComplete: () => Navigator.of(context).pop(),
          ),
        );
      }

      // Send the scheduled command to slaves
      _server.scheduleCommand('takePhoto', scheduledTime);

      // Master also waits until the scheduled time before executing
      await Future.delayed(scheduledTime.difference(DateTime.now()));

      // TODO: We should know before waiting? or we better wait even if we don't take pic?
      // Verify if master should also take a pic
      bool shouldMasterRecord = await SettingsService.getMasterShouldRecord();
      if (shouldMasterRecord) {
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

        _showPhotoDialog(capturedPhoto, autoClose: true);
      }

      final currentContext = context;

      if (currentContext.mounted){
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text("Photo scheduled for ${scheduledTime.toLocal()}")),
        );
      }

      LogService.instance.registerLog("Photo command executed by master at ${DateTime.now()}");
    }
    finally{
      setState(() {
        isProcessingTakePhoto = false; // Unlock button
      });
    }
  }


  void _showPhotoDialog(CapturedPhoto photo, {bool autoClose = false}) {
    AlertUtils.showMediaDialog(
      context: context,
      media: photo,
      isAutoCloseEnabled: autoClose,
      autoCloseSeconds: secondsToClosePhoto,
    );
  }

  void _showVideoDialog(CapturedVideo video, {bool autoClose = false}) {
    AlertUtils.showMediaDialog(
      context: context,
      media: video,
      isAutoCloseEnabled: autoClose,
      autoCloseSeconds: secondsToClosePhoto,
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



  Future<void> _createSession() async {

    if (isProcessingStartSession) return; // Prevent user from spamming

    setState(() {
      isProcessingStartSession = true; // Block the button
    });

    try{
      var sessionId = DateTime.now().toIso8601String();

      // Get the user GUID if logged in
      String? userGuid = UserService().guid;

      var response = await _apiService.createSession(
        sessionId,
        courtGuid: selectedCourtGuid,
        userGuid: userGuid, // Pass the user GUID if available
      );

      LogService.instance.registerLog("Response to create session: $response");

      if (response != null) {
        String sessionGuid = response['guid'];
        SessionManager.instance.startSession(sessionGuid, sessionId, deviceType: "Master");
        _server.startNewSession(sessionGuid); // Notify slaves

        LogService.instance.registerLog("Session created with GUID: $sessionGuid");

        setState(() {});
        if (context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Session created successfully: $sessionGuid")),
          );
        }
      } else {
        if (context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to create session")),
          );
        }
      }
    }
    finally{
      setState(() {
        isProcessingStartSession = false; // Desbloquea el botón
      });
    }
  }


  void _endCurrentSession() async {

    if (isProcessingEndSession) return; // Prevent spamming

    setState(() {
      isProcessingEndSession = true; // Block button
    });

    try{
      bool? confirmEnd = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("End Current Session"),
            content: const Text("Are you sure you want to end the current session?"),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () {
                  Navigator.of(context).pop(false); // Dont end
                },
              ),
              TextButton(
                child: const Text("End Session"),
                onPressed: () {
                  Navigator.of(context).pop(true); // Confirm end
                },
              ),
            ],
          );
        },
      );

      if (confirmEnd!= null && confirmEnd) {
        // Call API method endSession
        if (SessionManager.instance.currentSession != null) {
          bool success = await _apiService.endSession(SessionManager.instance.sessionGuid!);
          if (success) {
            _server.endCurrentSession(); // End locally
            setState((){});
            if (context.mounted){
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Capture session ended")),
              );
            }
          } else {
            if (context.mounted){
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Failed to end session on the server")),
              );
            }
          }
        }
      }
    }
    finally {
      setState(() {
        isProcessingEndSession = false; // Unlock button
      });
    }
  }

  // Method to show a modal with the connected device IDs
  void _showConnectedDevicesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        List<String> devices = getConnectedDevices();
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Connected Devices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (devices.isNotEmpty)
                ...devices.map((deviceId) => ListTile(
                  title: Text('Device ID: $deviceId'),
                ))
              else
                const Center(child: Text('No connected devices')),
            ],
          ),
        );
      },
    );
  }


  // Build the initial UI when no session is active
  Widget _buildInitialUI() {

    // Order courts and centers for widget
    Map<String, List<Map<String, String>>> sortedGroupedCourts = {
      for (var entry in (groupedCourts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) // Order centers
      )
        entry.key: entry.value..sort((a, b) => a['name']!.compareTo(b['name']!)) // Order courts
    };


    // Compute button width based on orientation
    final buttonWidth = MediaQuery.of(context).orientation == Orientation.portrait
        ? MediaQuery.of(context).size.width * 0.8 // 80% width when vertical
        : MediaQuery.of(context).size.width * 0.4; // 40% width when horizontal

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height, // Full screen height
          minWidth: MediaQuery.of(context).size.width
        ),
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
                    onPressed: isProcessingStartSession ? null : _startOrEndSession,
                    child: isProcessingStartSession
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
                      MaterialPageRoute(builder: (context) => SportsCentersScreen()),
                    ),
                    child: const Text("Or... Load a Previous One"),
                  ),
                ),
                const SizedBox(height:20),
                SizedBox(
                  width: buttonWidth,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const PreviousSessionsScreen()),
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
    String? sessionGuid = SessionManager.instance.sessionGuid;

    // Compute button width for vertical layout
    final buttonWidth = MediaQuery.of(context).orientation == Orientation.portrait
        ? MediaQuery.of(context).size.width * 0.8 // 80% width in portrait
        : MediaQuery.of(context).size.width * 0.4; // 40% width in landscape

    final double buttonDistance = MediaQuery.of(context).orientation == Orientation.portrait ? 10 : 5;

    // Buttons and connected devices widget
    Widget controls = Column(
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
            onPressed: sessionGuid != null && !isProcessingTakePhoto ? _takeRealPhoto : null,
            child: isProcessingTakePhoto
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Text("Take Photo"),
          ),
        ),
        SizedBox(height: buttonDistance),
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: sessionGuid != null ? _toggleRecording : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : Colors.green,
            ),
            child: Text(isRecording ? "Stop Recording" : "Start Recording"),
          ),
        ),
        SizedBox(height: buttonDistance),
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: isProcessingEndSession || sessionGuid == null ? null : _endCurrentSession,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: isProcessingEndSession
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text("End Session"),
          ),
        ),
        SizedBox(height: buttonDistance),
        SizedBox(
          width: buttonWidth,
          child: AddGalleryMediaButton(enabled: !isRecording),
        ),
      ],
    );

    // Media list widget
    Widget mediaList = MediaListWidget(
      photos: photos,
      videos: videos,
      onPhotoTap: (photo) => _showPhotoDialog(photo, autoClose: false), // No auto-close
      onVideoTap: (video) => _showVideoDialog(video, autoClose: false), // No auto-close
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
    String? sessionGuid = SessionManager.instance.sessionGuid;

    return WillPopScope(
      onWillPop: () async {
        if (isRecording) return false;

        // Handle the back button press
        _server.stopServer();
        _announcer.stopBroadcasting();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        );
        return false; // Prevent the default behavior
      },
      child: Scaffold(
        appBar: HydraCamAppBar(
          title: "HydraCam - Master Control",
          onBack: () {
            _server.stopServer();
            _announcer.stopBroadcasting();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
            );
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display session active status at the top
            Padding(
              padding: const EdgeInsets.all(8.0),
              child:  SessionInfoWidget(
                sessionDisplay: sessionActive ? "Session Active: $sessionGuid" : "No active session",
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
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
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
