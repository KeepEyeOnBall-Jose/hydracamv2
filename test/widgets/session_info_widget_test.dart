import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/session_info_widget.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("does not reload network info during parent rebuilds",
      (WidgetTester tester) async {
    var loadCount = 0;

    Future<Map<String, String?>> loadNetworkInfo() async {
      loadCount++;
      return {
        "networkType": "Wi-Fi (enable location for SSID)",
        "ip": "192.168.178.20",
      };
    }

    Widget buildWidget(String sessionDisplay) {
      return MaterialApp(
        home: Scaffold(
          body: SessionInfoWidget(
            sessionDisplay: sessionDisplay,
            networkInfoLoader: loadNetworkInfo,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWidget("No active session"));
    expect(find.text("Loading network info..."), findsOneWidget);

    await tester.pump();
    expect(
      find.text(
          "Network: Wi-Fi (enable location for SSID) | IP: 192.168.178.20"),
      findsOneWidget,
    );
    expect(loadCount, 1);

    await tester.pumpWidget(buildWidget("Session Active"));
    expect(find.text("Session: Session Active"), findsOneWidget);
    expect(find.text("Loading network info..."), findsNothing);
    expect(
      find.text(
          "Network: Wi-Fi (enable location for SSID) | IP: 192.168.178.20"),
      findsOneWidget,
    );
    expect(loadCount, 1);
  });

  testWidgets("long session and network labels fit narrow desktop panes",
      (WidgetTester tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(260, 220));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: SessionInfoWidget(
              sessionDisplay:
                  "session-20260608-wsl-linux-clean-build-after-dbus-guards",
              networkInfoLoader: () async => {
                "networkType":
                    "Wi-Fi (enable location for SSID and DBus system bus)",
                "ip": "172.23.68.143",
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
