import "package:flutter/material.dart";
import "../services/network_info_service.dart";

class SessionInfoWidget extends StatelessWidget {
  final String sessionDisplay;

  const SessionInfoWidget({
    super.key,
    required this.sessionDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Session: $sessionDisplay",
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        FutureBuilder<Map<String, String?>>(
          future: NetworkInfoService.getNetworkInfo(),
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
