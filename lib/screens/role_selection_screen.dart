import 'package:flutter/material.dart';
import '../master/master_screen.dart';
import '../slave/slave_screen.dart';

/// RoleSelectionScreen - Initial screen to select the role of the device (Master or Slave).
class RoleSelectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Select Device Role"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                // Navigate to MasterScreen when the Master role is selected
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => MasterScreen()),
                );
              },
              child: Text("Master Mode"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Navigate to SlaveScreen when the Slave role is selected
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SlaveScreen()),
                );
              },
              child: Text("Slave Mode"),
            ),
          ],
        ),
      ),
    );
  }
}
