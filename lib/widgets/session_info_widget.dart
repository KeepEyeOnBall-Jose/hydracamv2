import "package:flutter/material.dart";
import "../services/network_info_service.dart";

typedef NetworkInfoLoader = Future<Map<String, String?>> Function();

class SessionInfoWidget extends StatefulWidget {
  final String sessionDisplay;
  final NetworkInfoLoader? networkInfoLoader;

  const SessionInfoWidget({
    super.key,
    required this.sessionDisplay,
    this.networkInfoLoader,
  });

  @override
  State<SessionInfoWidget> createState() => _SessionInfoWidgetState();
}

class _SessionInfoWidgetState extends State<SessionInfoWidget> {
  late Future<Map<String, String?>> _networkInfoFuture;

  @override
  void initState() {
    super.initState();
    _networkInfoFuture = _loadNetworkInfo();
  }

  @override
  void didUpdateWidget(SessionInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.networkInfoLoader != oldWidget.networkInfoLoader) {
      _networkInfoFuture = _loadNetworkInfo();
    }
  }

  Future<Map<String, String?>> _loadNetworkInfo() {
    return (widget.networkInfoLoader ?? NetworkInfoService.getNetworkInfo)();
  }

  Widget _buildInfoText(
    String text, {
    int maxLines = 2,
    Color color = Colors.grey,
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

  @override
  Widget build(BuildContext context) {
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
                color: Colors.red,
              );
            } else {
              final data = snapshot.data!;
              final networkType = data["networkType"] ?? "Unknown Network";
              final ip = data["ip"] ?? "Unknown IP";
              return _buildInfoText(
                "Network: $networkType | IP: $ip",
              );
            }
          },
        ),
      ],
    );
  }
}
