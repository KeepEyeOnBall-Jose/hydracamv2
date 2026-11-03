import "package:flutter/services.dart";

import "../services/log_service.dart";

/// Values for a manual court enrollment (H2). [secret] is never logged.
class CourtEnrollmentInput {
  const CourtEnrollmentInput({
    required this.k2Url,
    required this.deviceId,
    required this.secret,
    required this.courtId,
    required this.slot,
    required this.mountRev,
  });

  final String k2Url;
  final String deviceId;
  final String secret;
  final String courtId;
  final String slot;
  final int mountRev;

  Map<String, Object?> toMap() => {
        "k2Url": k2Url,
        "deviceId": deviceId,
        "secret": secret,
        "courtId": courtId,
        "slot": slot,
        "mountRev": mountRev,
      };
}

/// Thin client for the `hydracam/court` channel served by `CourtActivity`.
/// The native runtime owns all court behaviour; Dart only shows status and
/// forwards enrollment.
class CourtChannel {
  CourtChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel("hydracam/court");

  final MethodChannel _channel;

  Future<Map<String, Object?>> status() async {
    final result = await _channel.invokeMapMethod<String, Object?>("status");
    return result ?? const <String, Object?>{};
  }

  /// Returns null on success, otherwise the validation error.
  Future<String?> enroll(CourtEnrollmentInput input) async {
    LogService.instance.registerLog(
      "Court enrollment requested for device ${input.deviceId} "
      "court ${input.courtId} slot ${input.slot}.",
      file: "court_channel.dart",
    );
    return _channel.invokeMethod<String>("enroll", input.toMap());
  }

  Future<void> clearEnrollment() async {
    LogService.instance.registerLog(
      "Court enrollment cleared.",
      file: "court_channel.dart",
    );
    await _channel.invokeMethod<void>("clearEnrollment");
  }

  Future<void> startService() => _channel.invokeMethod<void>("startService");
}
