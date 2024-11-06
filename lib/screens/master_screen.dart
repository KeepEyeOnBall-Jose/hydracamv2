import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart'; // Add video_player dependency in pubspec.yaml
import '../constants.dart';
import '../master/master_announcer.dart';
import '../master/master_server.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'dart:io';
import '../services/hydracam_api_service.dart';

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
      // End current session
      _endCurrentSession();
    } else {
      // Init the session
      await _createSession();
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

  void _startCamera() {
    _server.sendCommand('startCamera');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Start camera command sent to slaves")),
    );
  }

  void _simulateTakePhoto() {
    _server.sendCommand('simulateTakePhoto');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Simulate photo command sent")),
    );
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


  Future<void> _createSession() async {
    var sessionId = DateTime.now().toIso8601String();
    var response = await _apiService.createSession(
        sessionId,
        courtGuid: selectedCourtGuid
      );

    if (response != null) {
      sessionGuid = response['guid'];
      _server.startNewSession(); // Inicia la sesión en los dispositivos esclavos
      setState(() {
        sessionActive = true; // Cambia el estado a activo
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

  void _endCurrentSession() {
    _server.endCurrentSession(); // Termina la sesión en los dispositivos esclavos
    setState(() {
      sessionGuid = null;
      sessionActive = false; // Cambia el estado a inactivo
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Capture session ended")),
    );
  }

  void _selectCourt(String? courtName) {
    setState(() {
      selectedCourtName = courtName;
      selectedCourtGuid = courtName != null ? courts[courtName] : null;
    });
  }


  void _showCustomCourtDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController guidController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Enter Custom Court"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: "Court Name"),
              ),
              TextField(
                controller: guidController,
                decoration: InputDecoration(labelText: "Court GUID"),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Add Court"),
              onPressed: () {
                String courtName = nameController.text;
                String courtGuid = guidController.text;

                if (courtName.isNotEmpty && courtGuid.isNotEmpty) {
                  setState(() {
                    courts[courtName] = courtGuid;
                    selectedCourtName = courtName;
                    selectedCourtGuid = courtGuid;
                  });
                }

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _uploadAllMedia() async {
    if (sessionGuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No session GUID available. Create a session first.")),
      );
      return;
    }

    print("Now upload photos");
    for (var photo in photos) {
      var file = File(photo.photoPath);
      bool success = await _apiService.uploadMedia(sessionGuid!, file, true);
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
      bool success = await _apiService.uploadMedia(sessionGuid!, file, false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("HydraCam - Master Control"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedCourtName,
              hint: Text("Choose or add a Court"),
              isExpanded: false,
              items: [
                ...courts.keys.map((courtName) {
                  return DropdownMenuItem<String>(
                    value: courtName,
                    child: Text(courtName),
                  );
                }).toList(),
                DropdownMenuItem<String>(
                  value: "Custom",
                  child: Text("Custom..."),
                ),
              ],
              onChanged: (value) {
                if (value == "Custom") {
                  _showCustomCourtDialog();
                } else {
                  _selectCourt(value); // Llama a _selectCourt con el nuevo valor
                }
              },
            ),
            if (selectedCourtName != null)
              Text(
                "Selected Court: $selectedCourtName",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            SizedBox(height: 10),
            Text("Connected clients: $connectedClients"),
            //Text("Session ID: ${sessionId ?? 'Not started'}"),
            Text("Session GUID: ${sessionGuid ?? 'Not available'}"), //TODO: This in the class!!!

            SizedBox(height: 20),
            /*ElevatedButton(
              onPressed: () {
                _server.startNewSession();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("New capture session started")),
                );
              },
              child: Text("Start New Session"),
            ),*/
            // Botón único para iniciar/terminar sesión
            ElevatedButton(
              onPressed: _startOrEndSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: sessionActive ? Colors.red : Colors.green,
              ),
              child: Text(sessionActive ? "End Current Session" : "Start New Session"),
            ),
            /*ElevatedButton(
              onPressed: () {
                _server.endCurrentSession();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Capture session ended")),
                );
              },
              child: Text("End Current Session"),
            ),*/
            ElevatedButton(
              onPressed: _startCamera,
              child: Text("Start Camera on Slaves"),
            ),
            SizedBox(height: 20),
            /*ElevatedButton(
              onPressed: _simulateTakePhoto,
              child: Text("Simulate Take Photo on Slaves"),
            ),
            SizedBox(height: 20),*/
            ElevatedButton(
              onPressed: _takeRealPhoto,
              child: Text("Take Real Photo on Slaves"),
            ),
            ElevatedButton(
              onPressed: _toggleRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: isRecording ? Colors.red : Colors.green,
              ),
              child: Text(isRecording ? "Stop Recording Video" : "Start Recording Video"),
            ),

            ElevatedButton(
              onPressed: _uploadAllMedia,
              child: Text("Upload All Media"),
            ),

            Expanded(
              child: ListView.builder(
                itemCount: photos.length + videos.length,
                itemBuilder: (context, index) {
                  if (index < photos.length) {
                    final photo = photos[index];
                    return ListTile(
                      leading: Image.file(File(photo.photoPath), width: 50, height: 50),
                      title: Text("Photo from Slave: ${photo.slaveDeviceId}"),
                      subtitle: Text(
                        "Captured: ${photo.captureDate}\nReceived: ${photo.receivedDate}",
                      ),
                      onTap: () => _showPhotoDialog(photo),
                    );
                  } else {
                    final video = videos[index - photos.length];
                    return ListTile(
                      leading: Icon(Icons.videocam, size: 50),
                      title: Text("Video from Slave: ${video.slaveDeviceId}"),
                      subtitle: Text(
                        "Started: ${video.startRecordingDate}\nEnded: ${video.endRecordingDate}\nReceived: ${video.receivedDate}",
                      ),
                      onTap: () => _showVideoDialog(video),
                    );
                  }
                },
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
