/// This screen displays a list of available cameras on the device,
/// allows the user to see which one is currently selected (tap on it),
/// optionally previews a camera on long press,
/// blocks user interaction while cameras are loading/switching,
/// and ensures consistency in the CameraServiceSingleton.
library;

import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "../services/camera_service_singleton.dart";
import "../widgets/camera_preview_fitted.dart";

class CameraSelectionScreen extends StatefulWidget {
  const CameraSelectionScreen({super.key});

  @override
  State<CameraSelectionScreen> createState() => CameraSelectionScreenState();
}

class CameraSelectionScreenState extends State<CameraSelectionScreen> {
  /// Local copies of the camera list and the selected index.
  List<CameraDescription> _cameras = [];
  int _selectedIndex = 0;

  /// Whether the screen is in a "loading" state (e.g., switching cameras).
  /// We use this to block user interaction and show a spinner.
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  /// Loads the cameras from the singleton service and updates our local state accordingly.
  Future<void> _loadCameras() async {
    setState(() => _isLoading = true);

    final cameraService = CameraServiceSingleton.instance;
    await cameraService.initAvailableCameras();

    setState(() {
      _cameras = cameraService.deviceCameras;
      _selectedIndex = cameraService.selectedCameraIndex;
      _isLoading = false;
    });
  }

  /// Switches to a new camera index in the singleton service, and refreshes local state.
  Future<void> _onCameraSelected(int index) async {
    setState(() => _isLoading = true);

    final cameraService = CameraServiceSingleton.instance;
    await cameraService.switchCamera(index);

    setState(() {
      _selectedIndex = cameraService.selectedCameraIndex;
      _isLoading = false;
    });
  }

  /// Long press: confirm, then temporarily switch the global camera to [index] for a quick preview,
  /// and then switch back to the old camera index to remain consistent.
  Future<void> _onCameraLongPress(int index) async {
    // 1. Ask user to confirm opening the preview
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Open Camera Preview?"),
        content: Text(
          "Would you like to open a quick preview of camera '${_cameras[index].name}'?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Open"),
          ),
        ],
      ),
    );
    if (confirm != true) return; // User canceled or dismissed

    // 2. Save the old index, switch the global camera to [index]
    final cameraService = CameraServiceSingleton.instance;
    final oldIndex = cameraService.selectedCameraIndex;

    setState(() => _isLoading = true);
    await cameraService.switchCamera(index);
    setState(() => _isLoading = false);

    // 3. Show the preview in a dialog, using the same *global* camera controller
    //    so we remain consistent with the singleton.
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(8),
          // Use the new widget so the camera doesn't get distorted:
          child: CameraPreviewFitted(controller: cameraService.controller!),
        ),
      ),
    );

    // 4. Switch back to the old index so the user's original camera remains active
    setState(() => _isLoading = true);
    await cameraService.switchCamera(oldIndex);
    setState(() {
      _selectedIndex = cameraService.selectedCameraIndex;
      _isLoading = false;
    });
  }

  /// A helper method to get a user-friendly string from the lens direction.
  String _getOrientationString(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return "Back";
      case CameraLensDirection.front:
        return "Front";
      case CameraLensDirection.external:
        return "External";
      default:
        return "Unknown";
    }
  }

  /// Shows a simple help/instructions dialog.
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("How to use Camera Selection"),
        content: const Text(
          "• Tap on a camera to select it.\n"
          "• Long-press on a camera to quickly preview it (after a confirmation).\n"
          "• While a camera is loading, interactions are disabled.\n"
          "• The preview temporarily switches the global camera.\n"
          "  After closing, it returns to your original selection.\n",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    /// If still loading cameras (and we have none yet), just show a spinner.
    if (_isLoading && _cameras.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Camera Selection")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    /// If we loaded cameras but `_cameras.isEmpty`, no cameras found.
    if (_cameras.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Camera Selection")),
        body: const Center(child: Text("No cameras found on this device.")),
      );
    }

    /// We'll wrap the Scaffold in a Stack to place a loading overlay on top when needed.
    return Stack(
      children: [
        // 1) The main UI
        Scaffold(
          appBar: AppBar(
            title: const Text("Camera Selection"),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: _showHelpDialog,
              )
            ],
          ),
          body: ListView.builder(
            itemCount: _cameras.length,
            itemBuilder: (context, index) {
              final cameraDescription = _cameras[index];
              final isSelected = (index == _selectedIndex);

              return ListTile(
                title: Text('Camera "${cameraDescription.name}"'),
                subtitle: Text(
                  "Lens direction: ${_getOrientationString(cameraDescription.lensDirection)}",
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                // Tap => select camera
                onTap: _isLoading ? null : () => _onCameraSelected(index),
                // Long press => confirm & preview (temp switch -> show -> switch back)
                onLongPress:
                    _isLoading ? null : () => _onCameraLongPress(index),
              );
            },
          ),
        ),
        // 2) A semi-transparent loading overlay if _isLoading
        if (_isLoading)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
