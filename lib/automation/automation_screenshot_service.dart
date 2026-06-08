import "dart:io";
import "dart:ui" as ui;

import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";
import "package:path_provider/path_provider.dart";

class AutomationScreenshotService {
  AutomationScreenshotService._();

  static final GlobalKey repaintBoundaryKey =
      GlobalKey(debugLabel: "hydracamAutomationScreenshotBoundary");

  static Future<Map<String, dynamic>> capture(
      Map<String, dynamic> payload) async {
    final context = repaintBoundaryKey.currentContext;
    if (context == null) {
      throw StateError("Automation screenshot boundary is not mounted.");
    }

    final renderObject = context.findRenderObject();
    final pixelRatio = _pixelRatio(payload, View.of(context).devicePixelRatio);

    await SchedulerBinding.instance.endOfFrame;

    if (renderObject is! RenderRepaintBoundary) {
      throw StateError("Automation screenshot boundary is not renderable.");
    }

    final image = await renderObject.toImage(pixelRatio: pixelRatio);

    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError("Automation screenshot PNG encoding failed.");
      }

      final bytes = byteData.buffer.asUint8List();
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final screenshotsDirectory = Directory(
        "${documentsDirectory.path}/automation-screenshots",
      );
      await screenshotsDirectory.create(recursive: true);

      final fileName = _fileName(payload);
      final file = File("${screenshotsDirectory.path}/$fileName");
      await file.writeAsBytes(bytes, flush: true);

      return {
        "filePath": file.path,
        "appDataContainerSource": "Documents/automation-screenshots/$fileName",
        "width": image.width,
        "height": image.height,
        "pixelRatio": pixelRatio,
        "byteLength": bytes.length,
      };
    } finally {
      image.dispose();
    }
  }

  static double _pixelRatio(
    Map<String, dynamic> payload,
    double defaultPixelRatio,
  ) {
    final requested = payload["pixelRatio"];
    if (requested is num && requested > 0) {
      return requested.toDouble().clamp(0.5, 3.0).toDouble();
    }
    return defaultPixelRatio.clamp(0.5, 3.0).toDouble();
  }

  static String _fileName(Map<String, dynamic> payload) {
    final requested = payload["name"];
    final baseName = requested is String && requested.trim().isNotEmpty
        ? requested.trim()
        : "hydracam-automation-screenshot";
    final sanitized = baseName
        .replaceAll(RegExp(r"[^A-Za-z0-9._-]+"), "-")
        .replaceAll(RegExp(r"-+"), "-")
        .replaceAll(RegExp(r"(^-|-$)"), "");
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(":", "-")
        .replaceAll(".", "-");
    final safeBaseName =
        sanitized.isEmpty ? "hydracam-automation-screenshot" : sanitized;
    return "$safeBaseName-$timestamp.png";
  }
}
