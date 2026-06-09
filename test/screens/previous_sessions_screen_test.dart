import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/screens/previous_sessions_screen.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _PreviousSessionsPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  tearDownAll(() {
    pathProvider.dispose();
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

  void dispose() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  }
}
