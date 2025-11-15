import "package:flutter/material.dart";
import "../services/hydracam_api_service.dart";
import "../services/log_service.dart";
import "../services/session_manager.dart";

class SessionsScreen extends StatelessWidget {
  final String courtGuid;

  SessionsScreen({super.key, required this.courtGuid});

  final HydraCamApiService _apiService = HydraCamApiService();

  void _loadSession(BuildContext context, Map<String, dynamic> session) {
    LogService.instance.registerLog("Loading session: $session", function: "_loadSession", file: "sessions_screen.dart");

    // Start a session with SessionManager
    SessionManager.instance.startSession(session["guid"], session["sessionId"], deviceType: "Master");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Session loaded: ${session['sessionId']}")),
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
          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return Card(
                child: ListTile(
                  title: Text(session["sessionId"]),
                  subtitle: Text(
                    "Start: ${session['startTime']}\nEnd: ${session['endTime']}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download),
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
