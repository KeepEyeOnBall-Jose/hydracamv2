import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// A widget that wraps CameraPreview to maintain its true aspect ratio.
/// This helps prevent stretching or squashing when the phone is in portrait mode.
class CameraPreviewFitted extends StatelessWidget {
  final CameraController controller;

  const CameraPreviewFitted({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If the controller isn't initialized, show a loader or an empty container
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // The previewSize is set once the controller finishes initializing
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.shrink();
    }

    // Usually width > height for back cameras, but let's just compute aspect ratio
    final aspectRatio = previewSize.width / previewSize.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        // We'll try to use the full available width first
        double fittedWidth = maxWidth;
        double fittedHeight = fittedWidth / aspectRatio;

        // If that height is bigger than what's available, swap the logic
        if (fittedHeight > maxHeight) {
          fittedHeight = maxHeight;
          fittedWidth = fittedHeight * aspectRatio;
        }

        // Render the CameraPreview in a box of the appropriate size
        return SizedBox(
          width: fittedWidth,
          height: fittedHeight,
          child: CameraPreview(controller),
        );
      },
    );
  }
}
