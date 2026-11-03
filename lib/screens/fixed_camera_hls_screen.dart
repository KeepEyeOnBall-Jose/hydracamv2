import "dart:io";

import "package:flutter/material.dart";

import "../app_theme.dart";
import "../services/device_service.dart";
import "../services/fixed_camera_hls_recorder_service.dart";
import "../services/fixed_camera_hls_upload_bridge.dart";
import "../services/hls_stream_upload_queue.dart";
import "../services/hls_stream_upload_service.dart";
import "../services/log_service.dart";
import "../widgets/hls_player_view.dart";
import "../widgets/hydra_cam_app_bar.dart";

/// End-to-end fixed-camera HLS surface: record a local HLS bundle (synthetic or
/// real Camera2), replay it in-app, and upload it to media-timeline.
class FixedCameraHlsScreen extends StatefulWidget {
  const FixedCameraHlsScreen({super.key});

  @override
  State<FixedCameraHlsScreen> createState() => _FixedCameraHlsScreenState();
}

class _FixedCameraHlsScreenState extends State<FixedCameraHlsScreen> {
  final FixedCameraHlsRecorderService _service =
      FixedCameraHlsRecorderService();
  final TextEditingController _sessionController = TextEditingController(
    text: "fixed-camera-hls-${DateTime.now().millisecondsSinceEpoch}",
  );
  final TextEditingController _baseApiController = TextEditingController(
    text: "http://127.0.0.1:3001/api",
  );

  FixedCameraHlsCapabilities? _capabilities;
  String _deviceId = "fixed-court-a";
  bool _useCamera2 = false;
  FixedCameraHlsCameraMode? _selectedMode;
  bool _busy = false;

  String? _activeRecordingId;
  FixedCameraHlsRecordingResult? _finalized;
  String _status = "Loading capabilities…";
  String? _uploadSummary;

  bool get _isRecording => _activeRecordingId != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sessionController.dispose();
    _baseApiController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final capabilities = await _service.getCapabilities();
    final deviceId = await DeviceIdService.getOrCreateDeviceId();
    if (!mounted) {
      return;
    }
    setState(() {
      _capabilities = capabilities;
      _deviceId = deviceId;
      _useCamera2 =
          capabilities.canRecordCameraHls && capabilities.cameraIds.isNotEmpty;
      if (_useCamera2) {
        _selectedMode = _highestMode(capabilities);
      }
      _status = capabilities.channelAvailable
          ? "Ready (${capabilities.recorderMode ?? "unknown"} default)."
          : "Fixed-camera HLS channel unavailable on this platform.";
    });
  }

  Future<void> _startRecording() async {
    final capabilities = _capabilities;
    if (capabilities == null || _busy) {
      return;
    }
    final mode = _useCamera2 ? _selectedMode : null;
    final cameraId = !_useCamera2
        ? null
        : (mode?.cameraId ??
            (capabilities.cameraIds.isNotEmpty
                ? capabilities.cameraIds.first
                : null));
    final recordingId = "rec-${DateTime.now().millisecondsSinceEpoch}";
    setState(() {
      _busy = true;
      _finalized = null;
      _uploadSummary = null;
      _status = "Starting recording "
          "(${cameraId == null ? "synthetic" : "camera2 ${mode?.label ?? "default"}"})…";
    });
    try {
      final result = await _service.startRecording(
        FixedCameraHlsRecordingRequest(
          sessionGuid: _sessionController.text.trim(),
          deviceId: _deviceId,
          recordingId: recordingId,
          cameraId: cameraId,
          targetDurationSeconds: 4,
          width: mode?.width ?? 1920,
          height: mode?.height ?? 1080,
          frameRate: (mode?.maxFps ?? 30).clamp(1, 60),
          includeAudio: true,
        ),
      );
      LogService.instance.registerLog(
        "Fixed-camera HLS recording started: ${result.recordingId}",
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeRecordingId = recordingId;
        _status = "Recording ${result.recordingId}…";
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = "Start failed: $error");
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopRecording() async {
    final recordingId = _activeRecordingId;
    if (recordingId == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = "Finalizing $recordingId…";
    });
    try {
      final result = await _service.stopRecording(recordingId);
      LogService.instance.registerLog(
        "Fixed-camera HLS recording finalized: ${result.recordingId} "
        "(${result.chunkPaths.length} chunks)",
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeRecordingId = null;
        _finalized = result;
        _status = "Finalized ${result.recordingId} "
            "(${result.durationSeconds?.toStringAsFixed(2) ?? "?"}s, "
            "${result.chunkPaths.length} chunks).";
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _activeRecordingId = null;
          _status = "Stop failed: $error";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _upload() async {
    final finalized = _finalized;
    if (finalized == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _uploadSummary = null;
      _status = "Uploading ${finalized.recordingId}…";
    });
    try {
      final service = HlsStreamUploadService(
        baseApiUrl: _baseApiController.text.trim(),
      );
      final queue = HlsStreamUploadQueue(uploadService: service);
      final entry = await queue.addFinalizedRecording(
        sessionGuid: _sessionController.text.trim(),
        recording: finalized,
        deviceId: _deviceId,
      );
      await queue.startUploadingManually();
      final result = entry.result;
      if (!mounted) {
        return;
      }
      setState(() {
        if (entry.status == HlsStreamUploadQueueStatus.uploaded &&
            result != null) {
          _uploadSummary = "Uploaded: event=${result.eventId} "
              "file=${result.fileId} (${result.filename})";
          _status = "Upload complete.";
        } else {
          _uploadSummary = "Upload failed: ${entry.lastError ?? "unknown"}";
          _status = "Upload failed.";
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadSummary = "Upload error: $error";
          _status = "Upload failed.";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    final finalized = _finalized;
    return Scaffold(
      appBar: HydraCamAppBar(
        title: "Fixed-camera HLS",
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (capabilities != null) _buildCapabilitiesCard(capabilities),
            const SizedBox(height: 12),
            TextField(
              controller: _sessionController,
              decoration: const InputDecoration(
                labelText: "Session GUID",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseApiController,
              decoration: const InputDecoration(
                labelText: "media-timeline base API URL",
                border: OutlineInputBorder(),
              ),
            ),
            if (capabilities?.canRecordCameraHls ?? false)
              SwitchListTile(
                key: const Key("useCamera2Switch"),
                title: const Text("Use real Camera2 capture"),
                subtitle: Text(
                  "Cameras: ${capabilities!.cameraIds.join(", ")}",
                ),
                value: _useCamera2,
                onChanged: _isRecording || _busy
                    ? null
                    : (value) => setState(() => _useCamera2 = value),
              ),
            if (_useCamera2 && capabilities != null)
              _buildModeSelector(capabilities),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key("startRecordingButton"),
                    onPressed: _busy || _isRecording ? null : _startRecording,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text("Record"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key("stopRecordingButton"),
                    onPressed: _busy || !_isRecording ? null : _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (finalized != null) ...[
              ElevatedButton.icon(
                key: const Key("uploadButton"),
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.cloud_upload),
                label: const Text("Upload to media-timeline"),
              ),
              if (_uploadSummary != null) ...[
                const SizedBox(height: 8),
                Text(_uploadSummary!),
              ],
              const SizedBox(height: 16),
              const Text(
                "In-app replay",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildPlayer(finalized),
            ],
          ],
        ),
      ),
    );
  }

  /// Highest-resolution mode across every camera the device exposes.
  FixedCameraHlsCameraMode? _highestMode(
    FixedCameraHlsCapabilities capabilities,
  ) {
    final modes = [...capabilities.cameraModes]
      ..sort((a, b) => b.pixelCount.compareTo(a.pixelCount));
    return modes.isEmpty ? null : modes.first;
  }

  Widget _buildModeSelector(FixedCameraHlsCapabilities capabilities) {
    // List every recordable mode across all cameras; the label carries the
    // camera id + lens facing, and the selected mode drives which camera
    // records (see _startRecording).
    final modes = [...capabilities.cameraModes]
      ..sort((a, b) => b.pixelCount.compareTo(a.pixelCount));
    if (modes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<FixedCameraHlsCameraMode>(
        key: const Key("cameraModeDropdown"),
        initialValue: _selectedMode ?? modes.first,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: "Capture mode",
          border: OutlineInputBorder(),
        ),
        items: modes
            .map(
              (mode) => DropdownMenuItem<FixedCameraHlsCameraMode>(
                value: mode,
                child: Text(mode.label, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _isRecording || _busy
            ? null
            : (mode) => setState(() => _selectedMode = mode),
      ),
    );
  }

  Widget _buildCapabilitiesCard(FixedCameraHlsCapabilities capabilities) {
    return Card(
      color: AppTheme.appChrome.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("platform: ${capabilities.platform}"),
            Text("recorderMode: ${capabilities.recorderMode ?? "?"}"),
            Text(
              "supportedRecorderModes: "
              "${capabilities.supportedRecorderModes.join(", ")}",
            ),
            Text("cameraRecorder: ${capabilities.canRecordCameraHls}"),
            Text("cameraIds: ${capabilities.cameraIds.join(", ")}"),
            Text("deviceId: $_deviceId"),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer(FixedCameraHlsRecordingResult finalized) {
    final playlistPath = finalized.playlistPath;
    if (playlistPath == null) {
      return const Text("No playlist to play.");
    }
    final playlistFile = File(playlistPath);
    return HlsPlayerView(
      key: ValueKey(finalized.recordingId),
      bundleDirectory: playlistFile.parent,
      playlistName: playlistFile.uri.pathSegments.last,
    );
  }
}
