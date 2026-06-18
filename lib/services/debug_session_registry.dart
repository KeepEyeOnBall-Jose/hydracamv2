import "dart:convert";

import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

@immutable
class DebugSessionRef {
  const DebugSessionRef({
    required this.sessionGuid,
    required this.sessionId,
    this.serviceNumericId,
  });

  final String sessionGuid;
  final String sessionId;
  final int? serviceNumericId;

  Map<String, dynamic> toJson() {
    return {
      "sessionGuid": sessionGuid,
      "sessionId": sessionId,
      "serviceNumericId": serviceNumericId,
    };
  }

  factory DebugSessionRef.fromJson(Map<String, dynamic> json) {
    final rawNumericId = json["serviceNumericId"];
    return DebugSessionRef(
      sessionGuid: json["sessionGuid"].toString(),
      sessionId: json["sessionId"].toString(),
      serviceNumericId: rawNumericId is int
          ? rawNumericId
          : int.tryParse(rawNumericId?.toString() ?? ""),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DebugSessionRef &&
        other.sessionGuid == sessionGuid &&
        other.sessionId == sessionId &&
        other.serviceNumericId == serviceNumericId;
  }

  @override
  int get hashCode => Object.hash(sessionGuid, sessionId, serviceNumericId);
}

class DebugSessionRegistry {
  static const String _key = "debugSessionRegistry";

  Future<List<DebugSessionRef>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return raw
        .map((entry) => DebugSessionRef.fromJson(
              jsonDecode(entry) as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<void> record(DebugSessionRef ref) async {
    final refs = await list();
    final updated = [
      ...refs.where((item) => item.sessionGuid != ref.sessionGuid),
      ref,
    ];
    await _write(updated);
  }

  Future<void> remove(String sessionGuid) async {
    final refs = await list();
    await _write(
      refs.where((item) => item.sessionGuid != sessionGuid).toList(),
    );
  }

  Future<void> _write(List<DebugSessionRef> refs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      refs.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
