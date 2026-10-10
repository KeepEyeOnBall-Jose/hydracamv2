import "dart:convert";
import "dart:io";

import "package:integration_test/integration_test_driver_extended.dart";

Future<void> main() async {
  final output = Directory(Platform.environment["AUDIT_OUTPUT"] ??
      "logs/verification-runs/design-audit");
  await output.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      await File("${output.path}/$name.png").writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove("screenshots");
      await File("${output.path}/audit.json")
          .writeAsString(const JsonEncoder.withIndent("  ").convert(report));
    },
  );
}
