import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/log_service.dart";

void main() {
  setUp(() {
    LogService.instance.clearLogs();
  });

  test("registerLog stores message, timestamp, function, and file", () {
    final timestamp = DateTime(2026, 6, 7, 13, 30);

    LogService.instance.registerLog(
      "Profile startup marker",
      timestamp: timestamp,
      function: "main",
      file: "main.dart",
    );

    expect(LogService.instance.logs, hasLength(1));
    expect(
        LogService.instance.logs.single["message"], "Profile startup marker");
    expect(LogService.instance.logs.single["timestamp"], timestamp);
    expect(LogService.instance.logs.single["function"], "main");
    expect(LogService.instance.logs.single["file"], "main.dart");
  });

  test("clearLogs removes stored entries", () {
    LogService.instance.registerLog("temporary entry");

    LogService.instance.clearLogs();

    expect(LogService.instance.logs, isEmpty);
  });
}
