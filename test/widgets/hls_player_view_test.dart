import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/hls_player_view.dart";

void main() {
  testWidgets("shows loading indicator before the bundle resolves",
      (tester) async {
    final missing = Directory(
      "${Directory.systemTemp.path}/hls-missing-${DateTime.now().microsecondsSinceEpoch}",
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: HlsPlayerView(bundleDirectory: missing))),
    );
    // First synchronous frame, before the async _start() settles.
    expect(find.byKey(const Key("hlsPlayerLoading")), findsOneWidget);
  });

  testWidgets("surfaces an error when the bundle directory is missing",
      (tester) async {
    final missing = Directory(
      "${Directory.systemTemp.path}/hls-missing-${DateTime.now().microsecondsSinceEpoch}",
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: HlsPlayerView(bundleDirectory: missing))),
    );
    // Allow the async server start to fail and rebuild.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key("hlsPlayerError")), findsOneWidget);
  });
}
