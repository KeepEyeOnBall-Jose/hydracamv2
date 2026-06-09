import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/session_info_widget.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("session diagnostics visual proof", (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 260));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SessionInfoWidget(
              sessionDisplay: "Session Active: demo-session",
              networkInfoLoader: () async => {
                "networkType": "Wi-Fi (HydraCam Lab)",
                "ip": "192.168.178.20",
                "deviceId": "abcdef12-3456-7890",
                "appVersion": "1.2.3+45",
                "hardware": "iPhone 12 Pro",
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile("screenshots/session_identity_diagnostics.png"),
    );
  });
}
