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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Session: ${widget.sessionDisplay}",
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        FutureBuilder<Map<String, String?>>(
          future: _networkInfoFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Text(
                "Loading network info...",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              );
            } else if (snapshot.hasError) {
              return const Text(
                "Error fetching network info",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red,
                ),
              );
            } else {
              final data = snapshot.data!;
              final networkType = data["networkType"] ?? "Unknown Network";
              final ip = data["ip"] ?? "Unknown IP";
              return Text(
                "Network: $networkType | IP: $ip",
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
