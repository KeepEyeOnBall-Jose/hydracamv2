import "dart:async";

import "package:flutter/material.dart";
import "../models/capture_session.dart";
import "session_details_screen.dart";
import "../services/session_manager.dart";
import "../widgets/hydracam_surface.dart";

class PreviousSessionsScreen extends StatefulWidget {
  const PreviousSessionsScreen({super.key});

  @override
  PreviousSessionsScreenState createState() => PreviousSessionsScreenState();
}

class PreviousSessionsScreenState extends State<PreviousSessionsScreen> {
  Future<List<_StoredSessionListItem>> _availableSessions =
      Future<List<_StoredSessionListItem>>.value([]);

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
            builder: (context) => SessionDetailsScreen(
              session: session,
              storageIdentifier: sessionId,
            ),
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
      _availableSessions = _loadStoredSessions();
    });
  }

  Future<List<_StoredSessionListItem>> _loadStoredSessions() async {
    final sessionIds = await SessionManager.instance.getAvailableSessions();
    final storedSessions = <_StoredSessionListItem>[];
    for (final sessionId in sessionIds) {
      final session =
          await SessionManager.instance.loadSessionMetadataSnapshot(sessionId);
      storedSessions.add(
        _StoredSessionListItem(
          storageIdentifier: sessionId,
          session: session,
        ),
      );
    }
    return storedSessions;
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
      body: FutureBuilder<List<_StoredSessionListItem>>(
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
              final session = sessions[index];
              final legacySessionId = session.legacySessionId;
              return HydraCamSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text("Session: ${session.primaryIdentifier}"),
                  subtitle: legacySessionId == null
                      ? null
                      : Text("Legacy Session ID: $legacySessionId"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    unawaited(
                        _handleSessionTap(context, session.storageIdentifier));
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

class _StoredSessionListItem {
  const _StoredSessionListItem({
    required this.storageIdentifier,
    required this.session,
  });

  final String storageIdentifier;
  final CaptureSession? session;

  String get primaryIdentifier {
    return session?.preferredIdentifier ?? storageIdentifier;
  }

  String? get legacySessionId {
    final sessionId = session?.sessionId.trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        sessionId == primaryIdentifier) {
      return null;
    }
    return sessionId;
  }
}
