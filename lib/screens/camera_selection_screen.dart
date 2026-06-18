/// This screen displays a list of available cameras on the device,
/// allows the user to see which one is currently selected (tap on it),
/// optionally previews a camera on long press,
/// blocks user interaction while cameras are loading/switching,
/// and ensures consistency in the CameraServiceSingleton.
library;

import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "../app_theme.dart";
import "../models/camera_capture_settings.dart";
import "../services/camera_hardware_metadata_service.dart";
import "../services/camera_service_singleton.dart";
import "../services/log_service.dart";
import "../widgets/camera_preview_fitted.dart";

class CameraSelectionScreen extends StatefulWidget {
  const CameraSelectionScreen({super.key});

  @override
  State<CameraSelectionScreen> createState() => CameraSelectionScreenState();
}

class CameraSelectionScreenState extends State<CameraSelectionScreen> {
  /// Local copies of the camera list and the selected index.
  List<CameraDescription> _cameras = [];
  Map<String, CameraHardwareMetadata> _cameraMetadata = {};
  int _selectedIndex = 0;

  /// Whether the screen is in a "loading" state (e.g., switching cameras).
  /// We use this to block user interaction and show a spinner.
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  /// Loads the cameras from the singleton service and updates our local state accordingly.
  Future<void> _loadCameras() async {
    setState(() => _isLoading = true);

    final cameraService = CameraServiceSingleton.instance;
    try {
      await cameraService.initAvailableCameras();
      final cameras = cameraService.deviceCameras;
      final metadataEntries = await Future.wait(
        cameras.map((camera) async {
          final metadata =
              await CameraHardwareMetadataService.getCameraMetadata(
            camera.name,
          );
          return MapEntry(camera.name, metadata);
        }),
      );
      final metadata = <String, CameraHardwareMetadata>{};
      for (final entry in metadataEntries) {
        final value = entry.value;
        if (value != null) {
          metadata[entry.key] = value;
        }
      }

      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _cameraMetadata = metadata;
        _selectedIndex = cameraService.selectedCameraIndex;
        _errorMessage = _cameras.isEmpty
            ? "No cameras found. Check camera permissions and connections."
            : null;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Failed to load cameras: $error\n$stackTrace");
      if (!mounted) return;
      setState(() {
        _cameras = [];
        _errorMessage = "Camera access failed. Check permissions and retry.";
        _isLoading = false;
      });
      _showCameraSnackBar(_errorMessage!);
    }
  }

  /// Switches to a new camera index in the singleton service, and refreshes local state.
  Future<void> _onCameraSelected(int index) async {
    setState(() => _isLoading = true);

    final cameraService = CameraServiceSingleton.instance;
    try {
      await cameraService.switchCamera(index);

      if (!mounted) return;
      setState(() {
        _selectedIndex = cameraService.selectedCameraIndex;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Failed to switch camera: $error\n$stackTrace");
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showCameraSnackBar("Could not switch camera. Check camera access.");
    }
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
    try {
      await cameraService.switchCamera(index);
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Failed to open camera preview: $error\n$stackTrace");
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showCameraSnackBar("Could not open camera preview.");
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = false);

    final controller = cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      LogService.instance.registerLog(
          "Camera preview unavailable after selecting camera index $index.");
      _showCameraSnackBar("Camera preview is unavailable.");
      return;
    }

    // 3. Show the preview in a dialog, using the same *global* camera controller
    //    so we remain consistent with the singleton.
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(8),
          // Use the new widget so the camera doesn't get distorted:
          child: CameraPreviewFitted(controller: controller),
        ),
      ),
    );

    // 4. Switch back to the old index so the user's original camera remains active
    setState(() => _isLoading = true);
    try {
      await cameraService.switchCamera(oldIndex);
      if (!mounted) return;
      setState(() {
        _selectedIndex = cameraService.selectedCameraIndex;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      LogService.instance.registerLog(
          "Failed to restore camera selection: $error\n$stackTrace");
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showCameraSnackBar("Could not restore the previous camera.");
    }
  }

  void _showCameraSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getOrientationString(CameraLensDirection direction) {
    return switch (direction) {
      CameraLensDirection.back => "Back",
      CameraLensDirection.front => "Front",
      CameraLensDirection.external => "External",
    };
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
        body: Center(
          child: Text(_errorMessage ?? "No cameras found on this device."),
        ),
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
              final metadata =
                  _cameraMetadata[cameraDescription.name]?.detailText;

              return ListTile(
                title: Text('Camera "${cameraDescription.name}"'),
                subtitle: Text(
                  "${CameraLensLabels.describe(cameraDescription)} • "
                  "${_getOrientationString(cameraDescription.lensDirection)}"
                  "${metadata == null ? "" : " • $metadata"}",
                ),
                trailing: isSelected
                    ? const Icon(
                        Icons.check_circle,
                        color: AppTheme.accent,
                      )
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
            color: AppTheme.appChrome.withValues(alpha: 0.26),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
