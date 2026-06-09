import "../models/capture_session.dart";
import "session_manager.dart";

class GallerySessionCandidateSource {
  const GallerySessionCandidateSource();

  Future<List<CaptureSession>> load() async {
    final sessionManager = SessionManager.instance;
    final candidatesByKey = <String, CaptureSession>{};

    final activeSession = sessionManager.currentSession;
    if (activeSession != null) {
      _addSession(candidatesByKey, activeSession);
    }

    final availableSessionIds = await sessionManager.getAvailableSessions();
    for (final sessionId in availableSessionIds) {
      final snapshot =
          await sessionManager.loadSessionMetadataSnapshot(sessionId);
      if (snapshot != null) {
        _addSession(candidatesByKey, snapshot);
      }
    }

    return List.unmodifiable(candidatesByKey.values);
  }

  void _addSession(
    Map<String, CaptureSession> candidatesByKey,
    CaptureSession session,
  ) {
    final key = session.preferredIdentifier;
    candidatesByKey.putIfAbsent(key, () => session);
  }
}
