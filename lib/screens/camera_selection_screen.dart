/// camera_selection_screen.dart
///
/// This screen displays a list of available cameras on the device,
/// allows the user to see which one is currently selected,
/// and switch to a different camera without affecting the rest of the app flow.

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hydracam/services/camera_service_singleton.dart';

class CameraSelectionScreen extends StatefulWidget {
  const CameraSelectionScreen({Key? key}) : super(key: key);

  @override
  State<CameraSelectionScreen> createState() => _CameraSelectionScreenState();
}

class _CameraSelectionScreenState extends State<CameraSelectionScreen> {
  /// Local copies of the camera list and the selected index,
  /// to conveniently rebuild the UI after changes.
  List<CameraDescription> _cameras = [];
  int _selectedIndex = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  /// Loads the cameras from the singleton service
  /// and updates our local state accordingly.
  Future<void> _loadCameras() async {
    setState(() => _isLoading = true);

    final cameraService = CameraServiceSingleton.instance;

    // 1) Asegurar que el servicio ya consultó las cámaras
    //    (lo puedes llamar en un sitio más global si prefieres).
    await cameraService.initAvailableCameras();

    // 2) Actualizar el estado
    setState(() {
      _cameras = cameraService.deviceCameras;
      _selectedIndex = cameraService.selectedCameraIndex;
      _isLoading = false;
    });
  }

  /// Switches to a new camera index in the singleton service,
  /// and refreshes our local state.
  Future<void> _onCameraSelected(int index) async {
    setState(() => _isLoading = true);

    final cameraService = CameraServiceSingleton.instance;
    await cameraService.switchCamera(index);

    // After switching, update local states
    setState(() {
      _selectedIndex = cameraService.selectedCameraIndex;
      _isLoading = false;
    });
  }

  // Helper method to map the enum to a user-friendly string
  String _getOrientationString(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return 'Back';
      case CameraLensDirection.front:
        return 'Front';
      case CameraLensDirection.external:
        return 'External';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Simple loading indicator while we fetch cameras or switch camera
      return Scaffold(
        appBar: AppBar(title: const Text('Camera Selection')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_cameras.isEmpty) {
      // If no cameras available, show a message
      return Scaffold(
        appBar: AppBar(title: const Text('Camera Selection')),
        body: const Center(child: Text('No cameras found on this device.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Camera Selection')),
      body: ListView.builder(
        itemCount: _cameras.length,
        itemBuilder: (context, index) {
          final cameraDescription = _cameras[index];
          final isSelected = (index == _selectedIndex);

          return ListTile(
            title: Text('Camera "${cameraDescription.name}"'),
            subtitle: Text(
              'Lens direction: ${_getOrientationString(cameraDescription.lensDirection)}',
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            onTap: () => _onCameraSelected(index),
          );
        },
      ),
    );
  }
}
