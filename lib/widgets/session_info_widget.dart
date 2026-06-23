import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "../app_theme.dart";
import "../services/device_service.dart";
import "../services/log_service.dart";
import "../services/network_info_service.dart";

typedef NetworkInfoLoader = Future<Map<String, String?>> Function();

class SessionInfoWidget extends StatefulWidget {
  final String sessionDisplay;
  final NetworkInfoLoader? networkInfoLoader;
  final bool compact;
  final bool showDiagnostics;

  const SessionInfoWidget({
    super.key,
    required this.sessionDisplay,
    this.networkInfoLoader,
    this.compact = false,
    this.showDiagnostics = true,
  });

  @override
  State<SessionInfoWidget> createState() => _SessionInfoWidgetState();
}

class _SessionInfoWidgetState extends State<SessionInfoWidget> {
  late Future<Map<String, String?>> _networkInfoFuture;

  @override
  void initState() {
    super.initState();
    _networkInfoFuture =
        widget.showDiagnostics ? _loadNetworkInfo() : Future.value(const {});
  }

  @override
  void didUpdateWidget(SessionInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.networkInfoLoader != oldWidget.networkInfoLoader ||
        widget.showDiagnostics != oldWidget.showDiagnostics) {
      _networkInfoFuture =
          widget.showDiagnostics ? _loadNetworkInfo() : Future.value(const {});
    }
  }

  Future<Map<String, String?>> _loadNetworkInfo() {
    return (widget.networkInfoLoader ?? _loadDefaultDiagnostics)();
  }

  Future<Map<String, String?>> _loadDefaultDiagnostics() async {
    final diagnostics = await NetworkInfoService.getNetworkInfo();

    try {
      diagnostics["deviceId"] = await DeviceIdService.getOrCreateDeviceId();
    } catch (error) {
      LogService.instance
          .registerLog("Error loading diagnostics device ID: $error");
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      diagnostics["appVersion"] =
          "${packageInfo.version}+${packageInfo.buildNumber}";
    } catch (error) {
      LogService.instance
          .registerLog("Error loading diagnostics app version: $error");
    }

    try {
      final deviceInfo = await DeviceIdService.getDeviceInfo();
      diagnostics["hardware"] = _hardwareLabelFromDeviceInfo(deviceInfo);
      diagnostics["deviceId"] ??= deviceInfo["deviceId"]?.toString();
    } catch (error) {
      LogService.instance
          .registerLog("Error loading diagnostics hardware info: $error");
    }

    return diagnostics;
  }

  String? _hardwareLabelFromDeviceInfo(Map<String, dynamic> deviceInfo) {
    return _firstNonBlank([
      deviceInfo["modelName"],
      deviceInfo["model"],
      deviceInfo["name"],
      deviceInfo["platform"],
    ]);
  }

  String? _firstNonBlank(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Widget _buildInfoText(
    String text, {
    int maxLines = 2,
    Color color = AppTheme.textSecondary,
    FontWeight? fontWeight,
    double fontSize = 14,
  }) {
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        ),
      ),
    );
  }

  String _shortDeviceId(String? deviceId) {
    final normalized = deviceId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return "Unknown device";
    }
    if (normalized.length <= 8) {
      return normalized;
    }
    return normalized.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.compact) {
      return _buildStackedDiagnostics();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rawMaxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final maxWidth = rawMaxWidth <= 0 ? 180.0 : rawMaxWidth;
        final detailWidth = maxWidth >= 520 ? (maxWidth - 12) / 2 : maxWidth;

        Widget compactLine(
          String text, {
          double? width,
          Color color = AppTheme.textSecondary,
          FontWeight? fontWeight,
        }) {
          return SizedBox(
            width: width ?? detailWidth,
            child: _buildInfoText(
              text,
              maxLines: 1,
              color: color,
              fontSize: 13,
              fontWeight: fontWeight,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            compactLine(
              "Session: ${widget.sessionDisplay}",
              width: maxWidth,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
            if (widget.showDiagnostics) ...[
              const SizedBox(height: 4),
              FutureBuilder<Map<String, String?>>(
                future: _networkInfoFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return compactLine("Loading network info...");
                  } else if (snapshot.hasError) {
                    return compactLine(
                      "Error fetching network info",
                      color: AppTheme.danger,
                    );
                  }

                  final data = snapshot.data!;
                  final networkType = data["networkType"] ?? "Unknown Network";
                  final ip = data["ip"] ?? "Unknown IP";
                  final shortDeviceId = _shortDeviceId(data["deviceId"]);
                  final appVersion =
                      data["appVersion"] ?? "App version unavailable";
                  final hardware = data["hardware"] ?? "Hardware unavailable";

                  return Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      compactLine("Network: $networkType | IP: $ip"),
                      compactLine("Device: $shortDeviceId | App: $appVersion"),
                      compactLine("Hardware: $hardware"),
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStackedDiagnostics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoText(
          "Session: ${widget.sessionDisplay}",
          maxLines: 1,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        FutureBuilder<Map<String, String?>>(
          future: _networkInfoFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildInfoText(
                "Loading network info...",
                maxLines: 1,
              );
            } else if (snapshot.hasError) {
              return _buildInfoText(
                "Error fetching network info",
                maxLines: 1,
                color: AppTheme.danger,
              );
            } else {
              final data = snapshot.data!;
              final networkType = data["networkType"] ?? "Unknown Network";
              final ip = data["ip"] ?? "Unknown IP";
              final shortDeviceId = _shortDeviceId(data["deviceId"]);
              final appVersion =
                  data["appVersion"] ?? "App version unavailable";
              final hardware = data["hardware"] ?? "Hardware unavailable";
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoText(
                    "Network: $networkType | IP: $ip",
                  ),
                  _buildInfoText(
                    "Device: $shortDeviceId | App: $appVersion",
                    maxLines: 1,
                  ),
                  _buildInfoText(
                    "Hardware: $hardware",
                    maxLines: 1,
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }
}
