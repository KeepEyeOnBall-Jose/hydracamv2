import 'package:flutter/material.dart';
import '../widgets/session_info_widget.dart';
import 'master_screen.dart';
import 'slave_screen.dart';

/// RoleSelectionScreen - Initial screen to select the role of the device (Master or Slave).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // return false to prevent app from closing on pressing "back"
        return false;
      },

      child: Scaffold(
        appBar: AppBar(
          title: const Text("Select Device Role"),
          automaticallyImplyLeading: false, // Disable the "back" button
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start, // Center
            children: [

              // Display session active status at the top
              const Padding(
                padding: EdgeInsets.all(8.0),
                child:  SessionInfoWidget(
                  sessionDisplay: "No active session",
                ),
              ),

              const Spacer(),
              // Buttons
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to MasterScreen when the Master role is selected
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MasterScreen()),
                      );
                    },
                    child: const Text("Master Mode"),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to SlaveScreen when the Slave role is selected
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SlaveScreen()),
                      );
                    },
                    child: const Text("Slave Mode"),
                  ),
                ],
              ),
              const Spacer()
            ],
          ),
        ),
      ),
    );
  }
}
