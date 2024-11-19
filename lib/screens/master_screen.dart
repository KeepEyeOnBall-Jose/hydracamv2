import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart'; // Add video_player dependency in pubspec.yaml
import '../constants.dart';
import '../master/master_announcer.dart';
import '../master/master_server.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'dart:io';
import '../services/device_service.dart';
import '../services/hydracam_api_service.dart';
import '../widgets/Court_Selection_Widget.dart';

class MasterScreen extends StatefulWidget {
  @override
  _MasterScreenState createState() => _MasterScreenState();
}

class _MasterScreenState extends State<MasterScreen> {
  final MasterServer _server = MasterServer();
  final MasterAnnouncer _announcer = MasterAnnouncer(); // Broadcast announcer
  final HydraCamApiService _apiService = HydraCamApiService(); // API service instance

  int connectedClients = 0; // To display connected clients count
  bool isRecording = false;
  String? sessionGuid; // Store the session GUID from the API
  bool sessionActive = false;
  String? selectedCourtName;  // Name of the selected Court
  String? selectedCourtGuid;  // GUID of the selected Court (TODO: To be improved)

  List<CapturedPhoto> get photos => _server.currentSession?.capturedPhotos ?? [];
  List<CapturedVideo> get videos => _server.currentSession?.capturedVideos ?? [];

  List<String> getConnectedDevices() {
    return _server.getConnectedDeviceIds();
  }

  @override
  void initState() {
    super.initState();
    _server.onClientCountChange = (count) {
      setState(() {
        connectedClients = count;
      });
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
    _server.stopServer();
    _announcer.stopBroadcasting();
    super.dispose();
  }

  // Method to init a new session
  void _startOrEndSession() async {
    if (sessionActive) {
      // End the session
      _endCurrentSession();
    } else {
      // Start a new session
      if (selectedCourtGuid != null) {
        await _createSession();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please select a court before starting a session.")),
        );
      }
    }
  }


  void _toggleRecording() {
    if (isRecording) {
      _server.sendCommand('stopRecordingVideo');
      setState(() {
        isRecording = false;
      });
    } else {
      _server.sendCommand('startRecordingVideo');
      setState(() {
        isRecording = true;
      });
    }
  }

  void _takeRealPhoto() {
    _server.sendCommand('takePhoto');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Real photo command sent")),
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
                child: Text("Close"),
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
            style: TextStyle(fontSize: 16, color: Colors.blue),
          ),
          SizedBox(height: 10),
          Text(
            sessionActive ? "Session Active: $sessionGuid" : "No Active Session",
            style: TextStyle(fontSize: 16, color: Colors.black),
          ),
        ],
      ),
    );
  }



  Future<void> _createSession() async {
    var sessionId = DateTime.now().toIso8601String();
    var response = await _apiService.createSession(
        sessionId,
        courtGuid: selectedCourtGuid
      );

    if (response != null) {
      sessionGuid = response['guid'];
      _server.startNewSession(sessionGuid); // Init session in the slave devices
      setState(() {
        sessionActive = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session created successfully: $sessionGuid")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to create session")),
      );
    }
  }

  void _endCurrentSession() async {
    bool confirmEnd = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("End Current Session"),
          content: Text("Are you sure you want to end the current session?"),
          actions: [
            TextButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(false); // Dont end
              },
            ),
            TextButton(
              child: Text("End Session"),
              onPressed: () {
                Navigator.of(context).pop(true); // Confirm end
              },
            ),
          ],
        );
      },
    );

    if (confirmEnd == true) {
      // Call API method endSession
      if (sessionGuid != null) {
        bool success = await _apiService.endSession(sessionGuid!);
        if (success) {
          _server.endCurrentSession(); // End locally
          setState(() {
            sessionGuid = null;
            sessionActive = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Capture session ended")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to end session on the server")),
          );
        }
      }
    }
  }

  void _uploadAllMedia() async {

    if (photos.isEmpty && videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No media available to upload.")),
      );
      return;
    }

    if (sessionGuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No session GUID available. Create a session first.")),
      );
      return;
    }

    print("Now upload photos");
    for (var photo in photos) {
      var file = File(photo.photoPath);

      // Extract specific metadata for this photo
      String slaveDeviceId = photo.slaveDeviceId;
      DateTime captureDate = photo.captureDate;
      DateTime receivedDate = photo.receivedDate;

      bool success = await _apiService.uploadMedia(
        sessionGuid!,    // session GUID
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


    print("Now upload videos");
    for (var video in videos) {
      var file = File(video.videoPath);

      // Extract specific metadata for this video
      String slaveDeviceId = video.slaveDeviceId;
      DateTime captureDate = video.startRecordingDate;
      DateTime receivedDate = video.receivedDate;

      bool success = await _apiService.uploadMedia(
        sessionGuid!,    // session GUID
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
              Text('Connected Devices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              if (devices.isNotEmpty)
                ...devices.map((deviceId) => ListTile(
                  title: Text('Device ID: $deviceId'),
                ))
              else
                Center(child: Text('No connected devices')),
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
        SizedBox(height: 20),
        CourtSelectionWidget(
          groupedCourts: groupedCourts,
          onCourtSelected: (selectedName, selectedGuid) {
            setState(() {
              selectedCourtName = selectedName;
              selectedCourtGuid = selectedGuid;
            });
          },
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: selectedCourtGuid != null ? _startOrEndSession : null,
          child: Text("Start Session"),
        ),
      ],
    );
  }

  Widget _buildSessionUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _connectedDevicesWidget(),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: sessionGuid != null ? _takeRealPhoto : null,
          child: Text("Take Photo"),
        ),
        ElevatedButton(
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
        ElevatedButton(
          onPressed: (photos.isNotEmpty || videos.isNotEmpty) && sessionGuid != null
              ? _uploadAllMedia
              : null,
          child: Text("Upload All Media"),
        ),
        ElevatedButton(
          onPressed: sessionGuid != null ? _startOrEndSession : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text("End Session"),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("HydraCam - Master Control"),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () async {
              Map<String, dynamic> deviceInfo = await DeviceIdService.getDeviceInfo();
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text("Device Info"),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: deviceInfo.entries.map((entry) {
                        return Text('${entry.key}: ${entry.value}');
                      }).toList(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Close"),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Center(
        child: sessionActive ? _buildSessionUI() : _buildInitialUI(),
      ),
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
          CircularProgressIndicator(),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close"),
        ),
      ],
    );
  }
}
