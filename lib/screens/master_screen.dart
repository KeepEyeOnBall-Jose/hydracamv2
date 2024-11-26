import 'package:flutter/material.dart';
import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import 'package:video_player/video_player.dart'; // Add video_player dependency in pubspec.yaml
import '../constants.dart';
import '../master/master_announcer.dart';
import '../master/master_server.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'dart:io';
import '../services/camera_service.dart';
import '../services/hydracam_api_service.dart';
import '../services/log_service.dart';
import '../services/session_manager.dart';
import '../services/settings_service.dart';
import '../widgets/Court_Selection_Widget.dart';
import '../widgets/add_gallery_media_button.dart';
import '../widgets/hydra_cam_app_bar.dart';
import '../widgets/master_video_recording_screen.dart';
import '../widgets/media_list_widget.dart';

class MasterScreen extends StatefulWidget {
  @override
  _MasterScreenState createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final MasterServer _server = MasterServer(CameraService());
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
    LogService.instance.registerLog("PRESSED TOGGLE RECORDING. IS RECORDING = $isRecording");

    if (isRecording) {
      // Stop recording
      if (await SettingsService.getMasterShouldRecord()) {
        await _stopMasterRecordingVideo(); // Command is already sent from here
      } else {
        _server.sendCommand('stopRecordingVideo'); // Command sent explicitly
        setState(() {
          isRecording = false;
        });
      }
    } else {
      // Start recording
      _server.sendCommand('startRecordingVideo');
      if (await SettingsService.getMasterShouldRecord()) {
        await _startMasterRecordingVideo();
      } else {
        setState(() {
          isRecording = true;
        });
      }
    }
  }

  Future<void> _startMasterRecordingVideo() async {
    LogService.instance.registerLog("Will record from master and show preview");
    await _server.cameraService.startRecordingVideo();
    // Show camera preview overlay
    _showMasterVideoPreview();
  }

  Future<CapturedVideo> _stopMasterRecordingVideo() async {

    // Send command to slaves before stoppin from master
    _server.sendCommand('stopRecordingVideo');

    String videoPath = await _server.cameraService.stopRecordingVideo();

    // Add video to current session
    final receivedDate = DateTime.now();
    final capturedVideo = CapturedVideo(
      videoData: null,
      videoPath: videoPath,
      slaveDeviceId: "Master",
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



  void _showMasterVideoPreview() async {
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
      // Delay showing the dialog to prevent any touch event conflicts
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          _showVideoDialog(capturedVideo);
        }
      });
    }
  }

  void _takeRealPhoto() async {
    // Send command to slaves for taking pics
    _server.sendCommand('takePhoto');

    // Verify if master should also take a pic
    bool shouldMasterRecord = await SettingsService.getMasterShouldRecord();
    if (shouldMasterRecord) {
      final String photoPath = await _server.cameraService.takePhoto();

      // Add photo to current session
      final capturedPhoto = CapturedPhoto(
        photoData: null,
        photoPath: photoPath,
        captureDate: DateTime.now(),
        receivedDate: DateTime.now(),
        slaveDeviceId: "Master",
      );

      SessionManager.instance.addPhoto(capturedPhoto);

      setState(() {
      });

      // Show pop up for preview
      _showPhotoDialog(capturedPhoto);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Photo command sent to slaves")),
    );
  }

  void _showPhotoDialog(CapturedPhoto photo) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(File(photo.photoPath)),
              //Text("Captured: ${photo.captureDate}"),
              //Text("Received: ${photo.receivedDate}"),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVideoDialog(CapturedVideo video) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: VideoPlayerScreen(videoPath: video.videoPath),
        );
      },
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
    var sessionId = DateTime.now().toIso8601String();
    var response = await _apiService.createSession(
      sessionId,
      courtGuid: selectedCourtGuid,
    );

    LogService.instance.registerLog("Response to create session: $response");

    if (response != null) {
      String sessionGuid = response['guid'];
      SessionManager.instance.startSession(sessionGuid, deviceType: "Master");
      _server.startNewSession(sessionGuid); // Notify slaves

      LogService.instance.registerLog("Session created with GUID: $sessionGuid");

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session created successfully: $sessionGuid")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to create session")),
      );
    }
  }


  void _endCurrentSession() async {
    bool confirmEnd = await showDialog(
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

    if (confirmEnd) {
      // Call API method endSession
      if (SessionManager.instance.currentSession != null) {
        bool success = await _apiService.endSession(SessionManager.instance.sessionGuid!);
        if (success) {
          _server.endCurrentSession(); // End locally
          setState((){});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Capture session ended")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to end session on the server")),
          );
        }
      }
    }
  }

  void _uploadAllMedia() async {

    if (photos.isEmpty && videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No media available to upload.")),
      );
      return;
    }


    String? sessionGuid = SessionManager.instance.sessionGuid;

    if (sessionGuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No session GUID available. Create a session first.")),
      );
      return;
    }

    LogService.instance.registerLog("Now upload photos");
    for (var photo in photos) {
      var file = File(photo.photoPath);

      // Extract specific metadata for this photo
      String slaveDeviceId = photo.slaveDeviceId;
      DateTime captureDate = photo.captureDate;
      DateTime receivedDate = photo.receivedDate;

      bool success = await _apiService.uploadMedia(
        sessionGuid,    // session GUID
        file,            // actual file
        true,            // is photo? true for photo
        slaveDeviceId,   // ID from slave device id that took photo
        captureDate,     // capture date
        receivedDate,    // master reception date
      );

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to upload photo: ${photo.photoPath}")),
        );
        return;
      }
    }


    LogService.instance.registerLog("Now upload videos");
    for (var video in videos) {
      var file = File(video.videoPath);

      // Extract specific metadata for this video
      String slaveDeviceId = video.slaveDeviceId;
      DateTime captureDate = video.startRecordingDate;
      DateTime receivedDate = video.receivedDate;

      bool success = await _apiService.uploadMedia(
        sessionGuid,    // session GUID
        file,            // actual file
        false,           // is photo? false for video
        slaveDeviceId,   // ID from slave device id that took photo
        captureDate,     // capture date
        receivedDate,    // master reception date
      );

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to upload video: ${video.videoPath}")),
        );
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("All media uploaded successfully")),
    );
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


  Widget _buildInitialUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _connectedDevicesWidget(),
        const SizedBox(height: 20),
        CourtSelectionWidget(
          groupedCourts: groupedCourts,
          onCourtSelected: (selectedName, selectedGuid) {
            setState(() {
              selectedCourtName = selectedName;
              selectedCourtGuid = selectedGuid;
            });
          },
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _startOrEndSession, // Always clickable
          child: const Text("Start Session"),
        ),
      ],
    );
  }

  Widget _buildSessionUI() {


    String? sessionGuid = SessionManager.instance.sessionGuid;

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = constraints.maxWidth * 0.8; // El 80% del ancho total

        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _connectedDevicesWidget(),
            const SizedBox(height: 20),
            SizedBox(
              width: buttonWidth,
              child: ElevatedButton(
                onPressed: sessionGuid != null ? _takeRealPhoto : null,
                child: Text("Take Photo"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: buttonWidth,
              child: ElevatedButton(
                onPressed: sessionGuid != null
                    ? () {
                  _toggleRecording();
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRecording ? Colors.red : Colors.green,
                ),
                child: Text(isRecording ? "Stop Recording" : "Start Recording"),
              ),
            ),/*
            const SizedBox(height: 10),
            //TODO DELETE ME
            SizedBox(
              width: buttonWidth,
              child: ElevatedButton(
                onPressed: (photos.isNotEmpty || videos.isNotEmpty) && sessionGuid != null
                    ? _uploadAllMedia
                    : null,
                child: Text("Upload All Media"),
              ),
            ),*/
            const SizedBox(height: 10),
            SizedBox(
              width: buttonWidth,
              child: ElevatedButton(
                onPressed: sessionGuid != null ? _startOrEndSession : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("End Session"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: buttonWidth,
              child: const AddGalleryMediaButton(),
            ),
            const SizedBox(height: 20),
            // List to display photos and videos
            Expanded(
              child: MediaListWidget(
                photos: photos,
                videos: videos,
                onPhotoTap: _showPhotoDialog,
                onVideoTap: _showVideoDialog,
              ),
            ),
          ],
        );
      },
    );
  }


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
            MaterialPageRoute(builder: (context) => RoleSelectionScreen()),
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
              MaterialPageRoute(builder: (context) => RoleSelectionScreen()),
            );
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display session active status at the top
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                sessionActive
                    ? "Session Active: $sessionGuid"
                    : "",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            // Centered UI for session management
            Expanded(
              child: Center(
                child: sessionActive ? _buildSessionUI() : _buildInitialUI(),
              ),
            ),
          ],
        ),
      )
    );
  }

}

/// VideoPlayerScreen - A widget to play video using the video_player plugin.
class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;

  VideoPlayerScreen({required this.videoPath});

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
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
