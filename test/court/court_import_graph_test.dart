import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// H1: the court entrypoint must not reach the hand-held LAN servers, the
/// automation bridge or the Auth0 M2M service (and its embedded secret).
void main() {
  const forbidden = [
    "lib/services/auth0_m2m_service.dart",
    "lib/services/hydracam_api_service.dart",
    "lib/automation/automation_bridge.dart",
    "lib/master/master_server.dart",
    "lib/master/master_announcer.dart",
  ];

  test("court entrypoint import graph excludes hand-held services", () {
    final reachable = _reachableLibFiles("lib/court/main_court.dart");

    expect(reachable, contains("lib/court/court_status_screen.dart"));
    for (final path in forbidden) {
      expect(reachable, isNot(contains(path)), reason: "$path is reachable");
    }
    const shared = {"lib/services/log_service.dart", "lib/app_theme.dart"};
    final outsideAllowed = reachable.where(
      (path) => !path.startsWith("lib/court/") && !shared.contains(path),
    );
    expect(outsideAllowed, isEmpty);
  });
}

final _importPattern =
    RegExp(r"""^\s*(?:import|export)\s+["']([^"']+)["']""", multiLine: true);

Set<String> _reachableLibFiles(String entry) {
  final seen = <String>{};
  final pending = <String>[entry];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    final source = File(path).readAsStringSync();
    for (final match in _importPattern.allMatches(source)) {
      final target = _resolve(path, match.group(1)!);
      if (target != null) pending.add(target);
    }
  }
  return seen;
}

String? _resolve(String from, String uri) {
  if (uri.startsWith("dart:")) return null;
  if (uri.startsWith("package:")) {
    const own = "package:hydracam/";
    return uri.startsWith(own) ? "lib/${uri.substring(own.length)}" : null;
  }
  final base = File(from).parent.uri;
  final resolved = base.resolve(uri).toFilePath();
  final root = Directory.current.uri.toFilePath();
  return resolved.startsWith(root) ? resolved.substring(root.length) : resolved;
}
