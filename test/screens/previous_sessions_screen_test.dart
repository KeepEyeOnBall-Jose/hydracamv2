import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/screens/previous_sessions_screen.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _PreviousSessionsPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    pathProvider.resetDocumentsDir();
  });

  tearDown(() {
    pathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  testWidgets("stored media screen avoids local-session language",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PreviousSessionsScreen(),
      ),
    );
    await tester.pump();

    expect(find.text("Stored Media"), findsOneWidget);
    expect(find.textContaining("Local"), findsNothing);
  });

  testWidgets("late refresh completion after dispose does not throw",
      (tester) async {
    final releaseScan = Completer<void>();
    pathProvider.blockNextPathLookupUntil(releaseScan.future);

    await tester.pumpWidget(
      const MaterialApp(
        home: PreviousSessionsScreen(),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.shrink(),
      ),
    );

    releaseScan.complete();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets("stored media list prefers metadata GUID over storage key",
      (tester) async {
    pathProvider.writeSessionMetadata(
      storageIdentifier: "directory-reference-guid",
      sessionGuid: "backend-session-guid",
      sessionId: "legacy-session-id",
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: PreviousSessionsScreen(),
      ),
    );
    await _pumpUntilText(
      tester,
      "Session: backend-session-guid",
    );

    expect(find.text("Session: backend-session-guid"), findsOneWidget);
    expect(find.text("Legacy Session ID: legacy-session-id"), findsOneWidget);
    expect(find.textContaining("directory-reference-guid"), findsNothing);
    expect(find.textContaining("Service session:"), findsNothing);
  });
}

Future<void> _pumpUntilText(
  WidgetTester tester,
  String text, {
  int maxPumps = 100,
}) async {
  for (var pumpCount = 0; pumpCount < maxPumps; pumpCount += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
  }
}

class _PreviousSessionsPathProvider extends PathProviderPlatform {
  final Directory documentsDir =
      Directory.systemTemp.createTempSync("previous_sessions_screen_docs");
  Future<void>? _nextPathLookupBlocker;

  void blockNextPathLookupUntil(Future<void> blocker) {
    _nextPathLookupBlocker = blocker;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final blocker = _nextPathLookupBlocker;
    if (blocker != null) {
      _nextPathLookupBlocker = null;
      await blocker;
    }
    return documentsDir.path;
  }

  void resetDocumentsDir() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
    documentsDir.createSync(recursive: true);
  }

  void writeSessionMetadata({
    required String storageIdentifier,
    required String sessionGuid,
    required String sessionId,
  }) {
    final sessionDir =
        Directory("${documentsDir.path}/session_$storageIdentifier");
    sessionDir.createSync(recursive: true);
    File("${sessionDir.path}/metadata.json").writeAsStringSync(
      jsonEncode({
        "sessionId": sessionId,
        "sessionGuid": sessionGuid,
        "startTime": DateTime.utc(2026, 6, 18, 16).toIso8601String(),
        "endTime": DateTime.utc(2026, 6, 18, 17).toIso8601String(),
        "deviceType": "Master",
        "photos": [],
        "videos": [],
      }),
    );
  }

  void dispose() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  }
}
