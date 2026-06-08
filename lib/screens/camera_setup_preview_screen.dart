import "dart:async";

import "package:flutter/material.dart";

import "../models/capture_context_metadata.dart";
import "../services/camera_service.dart";
import "../services/camera_service_singleton.dart";
import "../services/camera_setup_service.dart";
import "../services/device_level_service.dart";
import "../services/log_service.dart";
import "../services/settings_service.dart";
import "../widgets/camera_level_overlay.dart";
import "../widgets/camera_preview_widget.dart";

class CameraSetupPreviewScreen extends StatefulWidget {
  const CameraSetupPreviewScreen({
    super.key,
    required this.onStartRecording,
    this.title = "Prepare Camera",
    this.preview,
    this.initialReading,
    this.initialPerspective,
    this.levelService,
  });

  final String title;
  final Widget? preview;
  final DeviceLevelReading? initialReading;
  final CameraPerspectiveMetadata? initialPerspective;
  final DeviceLevelService? levelService;
  final VoidCallback onStartRecording;

  @override
  State<CameraSetupPreviewScreen> createState() =>
      _CameraSetupPreviewScreenState();
}

class _CameraSetupPreviewScreenState extends State<CameraSetupPreviewScreen> {
  late final DeviceLevelService? _levelService;
  late final bool _ownsLevelService;
  late DeviceLevelReading _reading;
  late CameraPerspectiveMetadata _perspective;

  @override
  void initState() {
    super.initState();
    _ownsLevelService =
        widget.levelService == null && widget.initialReading == null;
    _levelService = widget.levelService ??
        (_ownsLevelService ? DeviceLevelService() : null);
    _reading = widget.initialReading ??
        _levelService?.reading.value ??
        DeviceLevelReading.unavailable();
    _perspective =
        widget.initialPerspective ?? CameraSetupService.instance.perspective;
    CameraSetupService.instance.setPerspective(_perspective);
    CameraSetupService.instance.updateLevelReading(_reading);

    _levelService?.reading.addListener(_handleLevelReadingChanged);
    _levelService?.start();

    if (widget.initialPerspective == null && widget.initialReading == null) {
      unawaited(_loadSavedPerspective());
    }
  }

  @override
  void dispose() {
    _levelService?.reading.removeListener(_handleLevelReadingChanged);
    if (_ownsLevelService) {
      unawaited(_levelService?.dispose());
    } else {
      unawaited(_levelService?.stop());
    }
    super.dispose();
  }

  void _handleLevelReadingChanged() {
    final reading = _levelService?.reading.value;
    if (reading == null) {
      return;
    }
    CameraSetupService.instance.updateLevelReading(reading);
    if (mounted) {
      setState(() {
        _reading = reading;
      });
    }
  }

  Future<void> _loadSavedPerspective() async {
    final perspective = await SettingsService.getCameraPerspective();
    CameraSetupService.instance.setPerspective(perspective);
    if (mounted) {
      setState(() {
        _perspective = perspective;
      });
    }
  }

  Future<void> _setPerspective(CameraPerspectiveMetadata perspective) async {
    CameraSetupService.instance.setPerspective(perspective);
    await SettingsService.setCameraPerspectiveId(
      perspective.cameraPerspectiveId,
    );
    if (mounted) {
      setState(() {
        _perspective = perspective;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: CameraSetupPreviewContent(
        preview: widget.preview,
        reading: _reading,
        perspective: _perspective,
        onPerspectiveChanged: _setPerspective,
        onStartRecording: widget.onStartRecording,
      ),
    );
  }
}

class CameraSetupPreviewPanel extends StatefulWidget {
  const CameraSetupPreviewPanel({
    super.key,
    this.title = "Prepare Camera",
    this.preview,
    this.initialReading,
    this.initialPerspective,
    this.levelService,
  });

  final String title;
  final Widget? preview;
  final DeviceLevelReading? initialReading;
  final CameraPerspectiveMetadata? initialPerspective;
  final DeviceLevelService? levelService;

  @override
  State<CameraSetupPreviewPanel> createState() =>
      _CameraSetupPreviewPanelState();
}

class CameraSetupStandaloneScreen extends StatefulWidget {
  const CameraSetupStandaloneScreen({
    super.key,
    this.title = "Prepare Camera",
  });

  final String title;

  @override
  State<CameraSetupStandaloneScreen> createState() =>
      _CameraSetupStandaloneScreenState();
}

class _CameraSetupStandaloneScreenState
    extends State<CameraSetupStandaloneScreen> {
  late final CameraService _cameraService;
  bool _isPreparingCamera = true;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _cameraService = CameraServiceSingleton.instance;
    unawaited(_prepareCamera());
  }

  @override
  void dispose() {
    unawaited(_cameraService.stopCamera());
    super.dispose();
  }

  Future<void> _prepareCamera() async {
    setState(() {
      _isPreparingCamera = true;
      _cameraError = null;
    });

    try {
      await _cameraService.ensureCameraIsReady();
    } catch (error, stackTrace) {
      LogService.instance.registerError(
        "Failed to prepare standalone setup camera preview",
        error,
        stackTrace,
      );
      _cameraError = error.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingCamera = false;
        });
      }
    }
  }

  Widget _previewWidget() {
    final controller = _cameraService.controller;
    if (controller != null && controller.value.isInitialized) {
      return CameraPreviewWidget(controller: controller);
    }

    if (_isPreparingCamera) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }

    return _CameraPreviewStatus(
      hasError: _cameraError != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: CameraSetupPreviewPanel(
        title: "Placement preview",
        preview: _previewWidget(),
      ),
    );
  }
}

class _CameraSetupPreviewPanelState extends State<CameraSetupPreviewPanel> {
  late final DeviceLevelService? _levelService;
  late final bool _ownsLevelService;
  late DeviceLevelReading _reading;
  late CameraPerspectiveMetadata _perspective;

  @override
  void initState() {
    super.initState();
    _ownsLevelService =
        widget.levelService == null && widget.initialReading == null;
    _levelService = widget.levelService ??
        (_ownsLevelService ? DeviceLevelService() : null);
    _reading = widget.initialReading ??
        _levelService?.reading.value ??
        DeviceLevelReading.unavailable();
    _perspective =
        widget.initialPerspective ?? CameraSetupService.instance.perspective;
    CameraSetupService.instance.setPerspective(_perspective);
    CameraSetupService.instance.updateLevelReading(_reading);

    _levelService?.reading.addListener(_handleLevelReadingChanged);
    _levelService?.start();

    if (widget.initialPerspective == null && widget.initialReading == null) {
      unawaited(_loadSavedPerspective());
    }
  }

  @override
  void dispose() {
    _levelService?.reading.removeListener(_handleLevelReadingChanged);
    if (_ownsLevelService) {
      unawaited(_levelService?.dispose());
    } else {
      unawaited(_levelService?.stop());
    }
    super.dispose();
  }

  void _handleLevelReadingChanged() {
    final reading = _levelService?.reading.value;
    if (reading == null) {
      return;
    }
    CameraSetupService.instance.updateLevelReading(reading);
    if (mounted) {
      setState(() {
        _reading = reading;
      });
    }
  }

  Future<void> _loadSavedPerspective() async {
    final perspective = await SettingsService.getCameraPerspective();
    CameraSetupService.instance.setPerspective(perspective);
    if (mounted) {
      setState(() {
        _perspective = perspective;
      });
    }
  }

  Future<void> _setPerspective(CameraPerspectiveMetadata perspective) async {
    CameraSetupService.instance.setPerspective(perspective);
    await SettingsService.setCameraPerspectiveId(
      perspective.cameraPerspectiveId,
    );
    if (mounted) {
      setState(() {
        _perspective = perspective;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CameraSetupPreviewContent(
      title: widget.title,
      preview: widget.preview,
      reading: _reading,
      perspective: _perspective,
      onPerspectiveChanged: _setPerspective,
    );
  }
}

class CameraSetupPreviewContent extends StatelessWidget {
  const CameraSetupPreviewContent({
    super.key,
    required this.reading,
    required this.perspective,
    required this.onPerspectiveChanged,
    this.preview,
    this.onStartRecording,
    this.title,
  });

  final String? title;
  final Widget? preview;
  final DeviceLevelReading reading;
  final CameraPerspectiveMetadata perspective;
  final Future<void> Function(CameraPerspectiveMetadata perspective)
      onPerspectiveChanged;
  final VoidCallback? onStartRecording;

  @override
  Widget build(BuildContext context) {
    final previewWidget =
        preview ?? _CameraPreviewPlaceholder(reading: reading);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CameraLevelOverlay(
                  reading: reading,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(child: previewWidget),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Camera perspective",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(perspective.cameraPerspectiveId),
              initialValue: perspective.cameraPerspectiveId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: CameraPerspectiveMetadata.canonicalPerspectives
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.cameraPerspectiveId,
                      child: Text(
                        option.cameraPerspectiveLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id == null) {
                  return;
                }
                unawaited(
                  onPerspectiveChanged(CameraPerspectiveMetadata.fromId(id)),
                );
              },
            ),
            if (onStartRecording != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onStartRecording,
                child: const Text("Start Recording"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraPreviewPlaceholder extends StatelessWidget {
  const _CameraPreviewPlaceholder({required this.reading});

  final DeviceLevelReading reading;

  @override
  Widget build(BuildContext context) {
    final icon = reading.sensorAvailable ? Icons.videocam : Icons.sensors_off;
    return Icon(icon, size: 56, color: Colors.white70);
  }
}

class _CameraPreviewStatus extends StatelessWidget {
  const _CameraPreviewStatus({required this.hasError});

  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Icon(
      hasError ? Icons.videocam_off : Icons.videocam,
      size: 56,
      color: Colors.white70,
    );
  }
}
