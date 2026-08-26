import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:http_parser/http_parser.dart";
import "package:package_info_plus/package_info_plus.dart";
import "log_service.dart";
import "auth0_m2m_service.dart";

part "api/hydracam_api_models.dart";
part "api/hydracam_api_http_core.dart";
part "api/hydracam_api_sessions_client.dart";
part "api/hydracam_api_media_client.dart";
part "api/hydracam_api_users_client.dart";

/// Singleton facade coordinating API communication for HydraCam.
///
/// The transport and configuration state live in [HydraCamApiHttpCore]; each
/// backend domain is served by a dedicated client ([HydraCamSessionsClient],
/// [HydraCamMediaUploadClient], [HydraCamUsersClient]) composed over that
/// shared core. This class keeps the historical public surface intact by
/// delegating every method to the appropriate client, so existing call sites
/// and tests remain unchanged.
class HydraCamApiService {
  // Singleton instance
  static final HydraCamApiService _instance = HydraCamApiService._internal();
  factory HydraCamApiService() => _instance;

  HydraCamApiService._internal();

  final HydraCamApiHttpCore _core = HydraCamApiHttpCore();
  late final HydraCamSessionsClient _sessions = HydraCamSessionsClient(_core);
  late final HydraCamMediaUploadClient _media =
      HydraCamMediaUploadClient(_core);
  late final HydraCamUsersClient _users = HydraCamUsersClient(_core);

  @visibleForTesting
  static void configureHttpClient(http.Client client) {
    _instance._core._httpClient = client;
  }

  @visibleForTesting
  static void resetHttpClient() {
    _instance._core._httpClient = http.Client();
  }

  @visibleForTesting
  static void configureBridgeRetryForTests({
    int? maxAttempts,
    Duration? initialDelay,
  }) {
    _instance._core.configureBridgeRetryForTests(
      maxAttempts: maxAttempts,
      initialDelay: initialDelay,
    );
  }

  @visibleForTesting
  static void configureBackendForTests({
    required HydraCamApiBackendMode mode,
    String? baseApiUrl,
  }) {
    _instance._core
        .configureBackendForTests(mode: mode, baseApiUrl: baseApiUrl);
  }

  @visibleForTesting
  static void resetBackendForTests() {
    _instance._core.resetBackendForTests();
  }

  void cancelInFlightRequests() => _core.cancelInFlightRequests();

  Future<List<Map<String, dynamic>>?> fetchCourts({String? sportsCenterGuid}) =>
      _sessions.fetchCourts(sportsCenterGuid: sportsCenterGuid);

  Future<List<Map<String, dynamic>>?> fetchSportsCenters() =>
      _sessions.fetchSportsCenters();

  Future<List<Map<String, dynamic>>?> fetchSessions(String courtGuid) =>
      _sessions.fetchSessions(courtGuid);

  Future<bool> notifyReadyToTransmit(String deviceId, String sessionGuid) =>
      _sessions.notifyReadyToTransmit(deviceId, sessionGuid);

  Future<bool> warmUpBackend({
    Duration timeout = HydraCamStartupWarmUpContract.timeout,
  }) =>
      _sessions.warmUpBackend(timeout: timeout);

  Future<HydraCamBackendSession?> createSession(
    String sessionId, {
    String? courtGuid,
    String? userGuid,
  }) =>
      _sessions.createSession(
        sessionId,
        courtGuid: courtGuid,
        userGuid: userGuid,
      );

  Future<bool> endSession(String sessionGuid) =>
      _sessions.endSession(sessionGuid);

  Future<bool> deleteDebugSession({
    required String sessionGuid,
    int? serviceNumericId,
  }) =>
      _sessions.deleteDebugSession(
        sessionGuid: sessionGuid,
        serviceNumericId: serviceNumericId,
      );

  Future<HydraCamDirectUploadStart?> startBridgeDirectUpload({
    required String sessionGuid,
    required String uploadToken,
    required String filename,
    required bool isPhoto,
    required String deviceId,
    DateTime? capturedAt,
    DateTime? receivedAt,
    int? sizeBytes,
    String? mimeType,
  }) =>
      _media.startBridgeDirectUpload(
        sessionGuid: sessionGuid,
        uploadToken: uploadToken,
        filename: filename,
        isPhoto: isPhoto,
        deviceId: deviceId,
        capturedAt: capturedAt,
        receivedAt: receivedAt,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
      );

  Future<bool> uploadMedia(
    String sessionGuid,
    File file,
    bool isPhoto,
    String slaveDeviceId,
    DateTime captureDate,
    DateTime receivedDate,
    Function(double)? onProgress, {
    DateTime? recordingEndDate,
    Duration? recordingDuration,
    String? mediaTimelineUploadToken,
    Function(String)? onFailureReason,
    Function(HydraCamUploadResult)? onUploadResult,
  }) =>
      _media.uploadMedia(
        sessionGuid,
        file,
        isPhoto,
        slaveDeviceId,
        captureDate,
        receivedDate,
        onProgress,
        recordingEndDate: recordingEndDate,
        recordingDuration: recordingDuration,
        mediaTimelineUploadToken: mediaTimelineUploadToken,
        onFailureReason: onFailureReason,
        onUploadResult: onUploadResult,
      );

  Future<String?> getUserGuidByEmail(String email) =>
      _users.getUserGuidByEmail(email);

  Future<Map?> fetchUserDetails(String guid) => _users.fetchUserDetails(guid);
}
