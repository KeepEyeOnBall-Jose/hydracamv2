import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// A widget that wraps CameraPreview and ensures a correct aspect ratio,
/// even if the raw camera preview is naturally landscape but the device is in portrait.
class CameraPreviewFitted extends StatelessWidget {
  final CameraController controller;

  const CameraPreviewFitted({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If the camera isn't initialized, show a loader
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.shrink();
    }

    // 1. Get the sensor orientation from the camera description
    final int sensorOrientation = controller.description.sensorOrientation;

    // 2. Compute the raw aspect ratio as the camera sees it
    //    Typically width > height for back cameras in "landscape" mode
    double aspectRatio = previewSize.width / previewSize.height;

    // 3. If the sensor orientation is 90 or 270, invert that ratio
    //    so we don't end up "squashed" in portrait
    if (sensorOrientation == 90 || sensorOrientation == 270) {
      aspectRatio = 1 / aspectRatio;
    }

    // 4. Use AspectRatio to enforce the camera’s ratio.
    //    That means if your device is portrait, the preview might have black bars
    //    (letterboxing) above or below, but won't look squashed.
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: CameraPreview(controller),
    );
  }
}
