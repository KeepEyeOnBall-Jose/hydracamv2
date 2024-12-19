import 'package:flutter/material.dart';
import 'package:hydracam/screens/session_details_screen.dart';
import '../services/session_manager.dart';

class PreviousSessionsScreen extends StatefulWidget {
  const PreviousSessionsScreen({super.key});

  @override
  _PreviousSessionsScreenState createState() => _PreviousSessionsScreenState();
}

class _PreviousSessionsScreenState extends State<PreviousSessionsScreen> {
  late Future<List<String>> _availableSessions;

  void _handleSessionTap(BuildContext context, String sessionId) async {
    // Store a reference to the current context
    final currentContext = context;

    // Load session metadata
    final session = await SessionManager.instance.loadSessionMetadata(sessionId);

    // Check if the context is still valid and the widget is mounted
    if (currentContext.mounted) {
      if (session != null) {
        Navigator.push(
          currentContext,
          MaterialPageRoute(
            builder: (context) => SessionDetailsScreen(session: session),
          ),
        );
      } else {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text("Failed to load session metadata.")),
        );
      }
    }
  }


  @override
  void initState() {
    super.initState();
    _availableSessions = SessionManager.instance.getAvailableSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Previous Sessions")),
      body: FutureBuilder<List<String>>(
        future: _availableSessions,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.data == null || snapshot.data!.isEmpty) {
            return const Center(child: Text("No previous sessions found."));
          }

          final sessions = snapshot.data!;
          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final sessionId = sessions[index];
              return ListTile(
                title: Text("Session: $sessionId"),
                onTap: () {
                  _handleSessionTap(context, sessionId);
                },
              );

            },
          );
        },
      ),
    );
  }
}
