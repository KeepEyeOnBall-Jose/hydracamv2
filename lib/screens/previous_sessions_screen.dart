import "dart:async";

import "package:flutter/material.dart";
import "session_details_screen.dart";
import "../services/session_manager.dart";

class PreviousSessionsScreen extends StatefulWidget {
  const PreviousSessionsScreen({super.key});

  @override
  PreviousSessionsScreenState createState() => PreviousSessionsScreenState();
}

class PreviousSessionsScreenState extends State<PreviousSessionsScreen> {
  Future<List<String>> _availableSessions = Future<List<String>>.value([]);

  Future<void> _handleSessionTap(BuildContext context, String sessionId) async {
    // Store a reference to the current context
    final currentContext = context;

    // Load session metadata
    final session =
        await SessionManager.instance.loadSessionMetadata(sessionId);

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

  Future<void> _refreshSessions() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _availableSessions = Future.value([]); // Clean view temporally
    });

    // Rebuilt previous sessions if needed
    await SessionManager.instance.scanAndReconstructSessions();

    if (!mounted) {
      return;
    }

    // Get available sessions after scan
    setState(() {
      _availableSessions = SessionManager.instance.getAvailableSessions();
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSessions());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Previous Sessions"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("Scanning and refreshing sessions...")),
              );
              unawaited(_refreshSessions());
            },
          ),
        ],
      ),
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
                  unawaited(_handleSessionTap(context, sessionId));
                },
              );
            },
          );
        },
      ),
    );
  }
}
