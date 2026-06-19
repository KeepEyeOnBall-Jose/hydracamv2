import "dart:io";

import "package:hydracam/models/hls_stream_bundle.dart";
import "package:hydracam/services/hls_stream_upload_queue.dart";
import "package:hydracam/services/hls_stream_upload_service.dart";

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  final directoryPath = options["directory"];
  final sessionGuid = options["session-guid"];
  final deviceId = options["device-id"];

  if (directoryPath == null || sessionGuid == null || deviceId == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    stderr.writeln("HLS directory does not exist: $directoryPath");
    exitCode = 66;
    return;
  }

  final capturedAt = options["captured-at"] == null
      ? DateTime.now().toUtc()
      : DateTime.parse(options["captured-at"]!).toUtc();
  final maxAttempts = _parsePositiveIntOption(
    options,
    "max-attempts",
    defaultValue: 3,
  );
  final retryDelayMs = _parseNonNegativeIntOption(
    options,
    "retry-delay-ms",
    defaultValue: 2000,
  );
  if (maxAttempts == null || retryDelayMs == null) {
    exitCode = 64;
    return;
  }
  final bundle = await HlsStreamBundle.fromDirectory(directory);
  final service = HlsStreamUploadService(
    baseApiUrl: options["base-api-url"] ?? "http://127.0.0.1:3001/api",
  );
  final queue = HlsStreamUploadQueue(
    uploadService: service,
    maxAttempts: maxAttempts,
    retryDelay: Duration(milliseconds: retryDelayMs),
  );
  final entry = queue.addBundle(
    sessionGuid: sessionGuid,
    bundle: bundle,
    deviceId: deviceId,
    capturedAt: capturedAt,
    recordingId: options["recording-id"],
    timingMetadata: _rawNativeTimingMetadata(options),
  );
  await queue.startUploadingManually();
  final result = entry.result;
  if (entry.status != HlsStreamUploadQueueStatus.uploaded || result == null) {
    stderr.writeln(
      "HLS upload failed after ${entry.attempts} attempt(s): "
      "${entry.lastError ?? "unknown error"}",
    );
    exitCode = 75;
    return;
  }

  stdout.writeln("Uploaded HLS stream:");
  stdout.writeln("  eventId: ${result.eventId}");
  stdout.writeln("  sessionGuid: ${result.sessionGuid}");
  stdout.writeln("  fileId: ${result.fileId}");
  stdout.writeln("  filename: ${result.filename}");
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (!arg.startsWith("--")) {
      continue;
    }
    final equalsIndex = arg.indexOf("=");
    if (equalsIndex > 2) {
      options[arg.substring(2, equalsIndex)] = arg.substring(equalsIndex + 1);
      continue;
    }
    final key = arg.substring(2);
    final nextIndex = index + 1;
    if (nextIndex < args.length && !args[nextIndex].startsWith("--")) {
      options[key] = args[nextIndex];
      index = nextIndex;
    } else {
      options[key] = "true";
    }
  }
  return options;
}

int? _parsePositiveIntOption(
  Map<String, String> options,
  String name, {
  required int defaultValue,
}) {
  final raw = options[name];
  if (raw == null) {
    return defaultValue;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 1) {
    stderr.writeln("--$name must be a positive integer.");
    return null;
  }
  return parsed;
}

int? _parseNonNegativeIntOption(
  Map<String, String> options,
  String name, {
  required int defaultValue,
}) {
  final raw = options[name];
  if (raw == null) {
    return defaultValue;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0) {
    stderr.writeln("--$name must be a non-negative integer.");
    return null;
  }
  return parsed;
}

HlsStreamTimingMetadata? _rawNativeTimingMetadata(Map<String, String> options) {
  final raw = options["native-timing-metadata-json"];
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return HlsStreamTimingMetadata.rawJson(raw);
}

void _printUsage() {
  stderr.writeln(
    "Usage: dart run scripts/upload_hls_bundle.dart "
    "--directory <hls-dir> --session-guid <guid-or-id> --device-id <device> "
    "[--base-api-url http://127.0.0.1:3001/api] "
    "[--recording-id game-1-camera-a] "
    "[--native-timing-metadata-json '{\"syncConfidence\":\"synthetic\"}'] "
    "[--captured-at 2026-06-19T10:00:00Z] "
    "[--max-attempts 3] [--retry-delay-ms 2000]",
  );
}
