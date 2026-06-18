import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/log_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _LogServicePathProvider();
  late Directory tempDir;

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    LogService.instance.clearLogs();
    tempDir = Directory.systemTemp.createTempSync("log_service_test");
    pathProvider.documentsPath = tempDir.path;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
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

  test("trace persistence retries after a transient path failure", () async {
    pathProvider.documentsPath = null;

    LogService.instance.registerLog("before path is ready");
    expect(await LogService.instance.readPersistedLogLines(), isEmpty);

    pathProvider.documentsPath = tempDir.path;
    LogService.instance.registerLog("after path is ready");

    final lines = await LogService.instance.readPersistedLogLines();

    expect(lines.join("\n"), contains("after path is ready"));
    expect(LogService.instance.traceFilePath, isNotNull);
  });

  test("trace persistence reports repeated path failures once", () async {
    final debugMessages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        debugMessages.add(message);
      }
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    pathProvider.documentsPath = null;

    LogService.instance.registerLog("first missing path log");
    LogService.instance.registerLog("second missing path log");
    expect(await LogService.instance.readPersistedLogLines(), isEmpty);

    expect(
      debugMessages
          .where((message) => message.startsWith("Trace file unavailable:")),
      hasLength(1),
    );
  });
}

class _LogServicePathProvider extends PathProviderPlatform {
  String? documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final path = documentsPath;
    if (path == null) {
      throw FileSystemException("documents path unavailable");
    }
    return path;
  }
}
