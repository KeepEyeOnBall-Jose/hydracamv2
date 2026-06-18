import "debug_session_registry.dart";
import "hydracam_api_service.dart";
import "log_service.dart";

class DebugSessionCleanupService {
  DebugSessionCleanupService({
    DebugSessionRegistry? registry,
    HydraCamApiService? apiService,
  })  : _registry = registry ?? DebugSessionRegistry(),
        _apiService = apiService ?? HydraCamApiService();

  final DebugSessionRegistry _registry;
  final HydraCamApiService _apiService;

  Future<int> deleteRegisteredDebugSessions() async {
    final refs = await _registry.list();
    var deletedCount = 0;
    for (final ref in refs) {
      final deleted = await _apiService.deleteDebugSession(
        sessionGuid: ref.sessionGuid,
        serviceNumericId: ref.serviceNumericId,
      );
      if (deleted) {
        await _registry.remove(ref.sessionGuid);
        deletedCount += 1;
      } else {
        LogService.instance.registerLog(
          "Debug session cleanup left registered session for retry: "
          "${ref.sessionGuid}",
        );
      }
    }
    return deletedCount;
  }
}
