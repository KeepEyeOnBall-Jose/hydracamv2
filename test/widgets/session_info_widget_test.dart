import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/session_info_widget.dart";

void main() {
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
}
