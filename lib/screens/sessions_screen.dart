import "package:flutter/material.dart";
import "../services/hydracam_api_service.dart";
import "../services/log_service.dart";
import "../services/session_manager.dart";
import "../widgets/hydracam_surface.dart";

class SessionsScreen extends StatelessWidget {
  final String courtGuid;

  SessionsScreen({super.key, required this.courtGuid});

  final HydraCamApiService _apiService = HydraCamApiService();

  String _primarySessionReference(Map<String, dynamic> session) {
    final guid = session["guid"]?.toString().trim();
    if (guid != null && guid.isNotEmpty) {
      return guid;
    }
    return session["sessionId"]?.toString() ?? "Unknown session";
  }

  String? _legacySessionId(Map<String, dynamic> session) {
    final sessionId = session["sessionId"]?.toString();
    final primaryReference = _primarySessionReference(session);
    if (sessionId == null ||
        sessionId.isEmpty ||
        sessionId == primaryReference) {
      return null;
    }
    return sessionId;
  }

  void _loadSession(BuildContext context, Map<String, dynamic> session) {
    LogService.instance.registerLog("Loading session: $session",
        function: "_loadSession", file: "sessions_screen.dart");

    final sessionReference = _primarySessionReference(session);

    // Join an existing service session with SessionManager
    SessionManager.instance.joinSession(
        sessionReference, session["sessionId"]?.toString(),
        deviceType: "Master");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Session loaded: $sessionReference")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sessions")),
      body: FutureBuilder<List<Map<String, dynamic>>?>(
        future: _apiService.fetchSessions(courtGuid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text("Failed to load sessions"));
          }

          final sessions = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final session = sessions[index];
              final legacySessionId = _legacySessionId(session);
              return HydraCamSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text("Session: ${_primarySessionReference(session)}"),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (legacySessionId != null)
                        Text("Legacy Session ID: $legacySessionId"),
                      Text("Start: ${session['startTime']}"),
                      Text("End: ${session['endTime']}"),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: "Load session",
                    onPressed: () {
                      _loadSession(context, session);
                      Navigator.pop(context); // Return to Courts
                      Navigator.pop(context); // Return to Sports Centers
                      Navigator.pop(context); // Return to Master Screen
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
