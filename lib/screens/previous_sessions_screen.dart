import "dart:async";

import "package:flutter/material.dart";
import "session_details_screen.dart";
import "../services/session_manager.dart";
import "../widgets/hydracam_surface.dart";

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
        title: const Text("Stored Media"),
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
            return const Center(child: Text("No stored media found."));
          }

          final sessions = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final sessionId = sessions[index];
              return HydraCamSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text("Service session: $sessionId"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    unawaited(_handleSessionTap(context, sessionId));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
