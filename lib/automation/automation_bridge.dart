import "dart:async";
import "dart:convert";
import "dart:io";

import "automation_config.dart";
import "../services/log_service.dart";
import "../services/session_manager.dart";
import "../services/settings_service.dart";
import "../services/uploader_service.dart";

typedef AutomationHandler = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> payload);

/// Exposes a lightweight HTTP endpoint (guarded behind HYDRACAM_AUTOMATION)
/// so that the Python orchestrator can trigger commands and gather state.
class AutomationBridge {
  AutomationBridge._();

  static final AutomationBridge instance = AutomationBridge._();

  final Map<String, AutomationHandler> _handlers = {};
  HttpServer? _server;
  bool _initialized = false;

  // Callback to get current recording state from master screen
  bool Function()? getRecordingState;

  Future<void> ensureInitialized() async {
    if (_initialized || !automationEnabled) {
      return;
    }

    await _startServer();
    _initialized = true;
    LogService.instance.registerLog(
        "Automation bridge listening on port $automationServerPort");
  }

  void registerCommand(String command, AutomationHandler handler) {
    _handlers[command] = handler;
  }

  void unregisterCommands(Iterable<String> commands) {
    for (final command in commands) {
      _handlers.remove(command);
    }
  }

  Map<String, dynamic> buildSessionSnapshot() {
    final session = SessionManager.instance.currentSession;
    return {
      "sessionGuid": SessionManager.instance.sessionGuid,
      "deviceType": SessionManager.instance.deviceType,
      "isActive": SessionManager.instance.isSessionActive,
      "photoCount": session?.capturedPhotos.length ?? 0,
      "videoCount": session?.capturedVideos.length ?? 0,
      "queueLength": UploaderService().queueLength,
      "isUploading": UploaderService().isUploading,
      "isRecording": getRecordingState?.call() ?? false,
    };
  }

  Future<void> _startServer() async {
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      automationServerPort,
    );
    _server!.listen(
      _handleRequest,
      onError: (error, stackTrace) {
        LogService.instance
            .registerLog("Automation bridge error: $error\n$stackTrace");
      },
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == "GET" && request.uri.path == "/healthz") {
        await _respond(request, {"status": "ok", "automation": true});
        return;
      }

      if (request.method == "GET" && request.uri.path == "/session") {
        await _respond(request, buildSessionSnapshot());
        return;
      }

      if (request.method == "GET" && request.uri.path == "/logs") {
        await _respond(request, {
          "logs": LogService.instance.logs
              .map((entry) => {
                    "message": entry["message"],
                    "timestamp":
                        (entry["timestamp"] as DateTime?)?.toIso8601String(),
                    "function": entry["function"],
                    "file": entry["file"],
                  })
              .toList(),
        });
        return;
      }

      if (request.method == "POST" && request.uri.path == "/settings") {
        final payload = await _decodeBody(request);
        await _applySettings(payload);
        await _respond(request, {"status": "ok"});
        return;
      }

      if (request.method == "POST" &&
          request.uri.pathSegments.length == 2 &&
          request.uri.pathSegments.first == "commands") {
        final command = request.uri.pathSegments[1];
        final handler = _handlers[command];
        if (handler == null) {
          await _respond(
            request,
            {
              "error": "unknown_command",
              "command": command,
            },
            statusCode: HttpStatus.notFound,
          );
          return;
        }

        final payload = await _decodeBody(request);
        final result = await handler(payload);
        await _respond(request, {
          "status": "ok",
          "command": command,
          "result": result,
        });
        return;
      }

      await _respond(
        request,
        {
          "error": "unsupported_route",
          "path": request.uri.path,
        },
        statusCode: HttpStatus.notFound,
      );
    } catch (error, stackTrace) {
      LogService.instance
          .registerLog("Automation request failure: $error\n$stackTrace");
      await _respond(
        request,
        {
          "error": "bridge_failure",
          "details": error.toString(),
        },
        statusCode: HttpStatus.internalServerError,
      );
    }
  }

  Future<Map<String, dynamic>> _decodeBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException("Expected JSON object in request body");
  }

  Future<void> _respond(HttpRequest request, Map<String, dynamic> payload,
      {int statusCode = HttpStatus.ok}) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType =
        ContentType("application", "json", charset: "utf-8");
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  Future<void> _applySettings(Map<String, dynamic> payload) async {
    final futures = <Future<void>>[];

    payload.forEach((key, value) {
      switch (key) {
        case "autoUploadMaterials":
          futures.add(SettingsService.setAutoUploadMaterials(_asBool(value)));
          break;
        case "masterShouldRecord":
          futures.add(SettingsService.setMasterShouldRecord(_asBool(value)));
          break;
        case "deleteLocalAfterUpload":
          futures
              .add(SettingsService.setDeleteLocalAfterUpload(_asBool(value)));
          break;
        case "autoplayVideoOnMaster":
          futures.add(SettingsService.setAutoplayVideoOnMaster(_asBool(value)));
          break;
        case "flashForVideoAnnounce":
          futures.add(SettingsService.setFlashForVideoAnnounce(_asBool(value)));
          break;
        case "timerDuration":
          futures.add(SettingsService.setTimerDuration(_asInt(value)));
          break;
        default:
          LogService.instance
              .registerLog("Ignoring unknown automation setting: $key");
      }
    });

    await Future.wait(futures);
  }

  bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.toLowerCase() == "true";
    }
    throw ArgumentError("Cannot convert $value to bool");
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) {
      return int.parse(value);
    }
    throw ArgumentError("Cannot convert $value to int");
  }
}
