import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import '../globals.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/log_service.dart';
import '../services/session_manager.dart';
import '../slave/slave_client.dart';
import '../slave/master_discovery.dart';
import '../widgets/hydra_cam_app_bar.dart';
import '../widgets/media_list_widget.dart';
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
  bool isConnected = false;
  String statusMessage = "Waiting for camera commands...";
  Timer? autoModeTimer; // Timer for auto mode logic
  bool isRecording = false;

  // Getters for SessionManager photos and videos
  List<CapturedPhoto> get photos => SessionManager.instance.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos => SessionManager.instance.currentSession?.capturedVideos ?? [];

  MasterDiscovery? _masterDiscovery; // So we can store instance of master_discovery and properly dispose it on screen change

  @override
  void initState() {
    super.initState();

    _masterDiscovery = MasterDiscovery(onMasterDiscovered: (masterIp) {
      if (!isConnected) {
        LogService.instance.registerLog("Connecting to master at IP: $masterIp");
        _client = SlaveClient(
          'ws://$masterIp:4040/ws',
          onPhotoTaken: (path) {
            if (!mounted) return;
            setState(() {
              statusMessage = "Photo taken!";
            });
            LogService.instance.registerLog("Photo taken!!!");

            // Flag to track if the dialog is still open
            bool isDialogOpen = true;

            // Show the taken photo in a modal
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Photo Taken"),
                content: Image.file(File(path)),
                actions: [
                  TextButton(
                    onPressed: () {
                      // Mark the dialog as closed and manually close it
                      isDialogOpen = false;
                      Navigator.pop(context);
                    },
                    child: const Text("Close"),
                  ),
                ],
              ),
            ).then((_) {
              // When the dialog is closed (manually or automatically), mark it as closed
              isDialogOpen = false;
            });

            // Automatically close after N seconds
            Future.delayed(Duration(seconds: secondsToClosePhoto), () {
              if (isDialogOpen && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            });
          },
          onRecordingStarted: _handleRecordingStarted,
          onRecordingStopped: _handleRecordingStopped,
        );
        _client?.connect();


        // Listen to the client's status stream
        _statusSubscription = _client?.statusStream.listen((message) {
          if (mounted) {
            setState(() {
              statusMessage = message;
            });
          }
        });


        setState(() {
          isConnected = true;
          statusMessage = "Connected to master at $masterIp";
        });

        if (widget.isAutoMode) {
          autoModeTimer?.cancel(); // Stop auto mode if master is found
        }
      }
    });

    _masterDiscovery?.startListening();


    if (widget.isAutoMode) {
      // Automatically transition to MasterScreen if no master is found
      autoModeTimer = Timer(Duration(seconds: timeToStopSearching), () {
        if (!isConnected) {
          LogService.instance.registerLog("No master found, switching to Master mode.");
          _transitionToMasterScreen();
        }
      });
    }

  }

  void _handleRecordingStarted() {
    if(mounted){
      setState(() {
        isRecording = true;
      });
    }
  }

  void _handleRecordingStopped() {
    if (mounted) {
      setState(() {
        isRecording = false;
      });
    }
  }


  void _transitionToMasterScreen() {
    // Stop any activity related to Slave
    _cleanUpSlaveMode();

    // Move to master screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MasterScreen()),
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


  @override
  void dispose() {
    try{
      _statusSubscription?.cancel(); // Cancel the subscription to avoid memory leaks
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    String sessionDisplay = SessionManager.instance.sessionGuid ?? "No active session";    // Get current session

    return WillPopScope(
      onWillPop: () async {
        _cleanUpSlaveMode();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => RoleSelectionScreen()),
        );
        return false;
      },
      child: Scaffold(
        appBar: HydraCamAppBar(
          title: "HydraCam - Slave Device",
          onBack: () {
            _cleanUpSlaveMode();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => RoleSelectionScreen()),
            );
          },
        ),
        body: Column(
          children:[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "Session: $sessionDisplay",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            Expanded(
              child: Stack(
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
              )
            ),
            // Photo and video list
            Expanded(
              child: MediaListWidget(
                photos: photos,
                videos: videos,
                onPhotoTap: _showPhotoDialog,
                onVideoTap: _showVideoDialog,
              ),
            ),
          ]
        ),
      ),
    );
  }
// TODO: EXTRACT TO WIDGET TO AVOID REPEAT CODE WITH MASTER
  void _showPhotoDialog(CapturedPhoto photo) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(File(photo.photoPath)),
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
}
