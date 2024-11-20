import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import '../globals.dart';
import '../slave/slave_client.dart';
import '../slave/master_discovery.dart';
import '../widgets/hydra_cam_app_bar.dart';
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
  bool isConnected = false;
  String statusMessage = "Waiting for camera commands...";
  Timer? autoModeTimer; // Timer for auto mode logic

  MasterDiscovery? _masterDiscovery; // So we can store instance of master_discovery and properly dispose it on screen change


  @override
  void initState() {
    super.initState();

    _masterDiscovery = MasterDiscovery(onMasterDiscovered: (masterIp) {
      if (!isConnected) {
        if (kDebugMode) {
          print("Connecting to master at IP: $masterIp");
        }
        _client = SlaveClient(
          'ws://$masterIp:4040/ws',
          onPhotoTaken: (path) {
            setState(() {
              statusMessage = "Photo taken!";
            });
            if (kDebugMode) {
              print("Photo taken!!!");
            }

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
        );
        _client?.connect();
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
          if (kDebugMode) {
            print("No master found, switching to Master mode.");
          }
          _transitionToMasterScreen();
        }
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
    _client?.disconnect();
    _client = null;
    autoModeTimer?.cancel();
    autoModeTimer = null;
    _masterDiscovery?.stopListening();
    _masterDiscovery = null;

    if (kDebugMode) {
      print("Cleaned up Slave mode.");
    }
  }


  @override
  void dispose() {
    try{
      _client?.disconnect();
      _client = null;
      autoModeTimer?.cancel();
      autoModeTimer = null;
      _masterDiscovery?.stopListening();
      _masterDiscovery = null;
    }
    catch(e){
      if (kDebugMode) {
        print(e);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Handle the back button press
        _cleanUpSlaveMode();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => RoleSelectionScreen()),
        );
        return false; // Prevent the default behavior
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(statusMessage),
              SizedBox(height: 20)
              // Here camera preview or something
              ,
            ],
          ),
        ),
      ),
    );
  }
}
