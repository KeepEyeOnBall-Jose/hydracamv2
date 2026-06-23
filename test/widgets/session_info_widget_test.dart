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
        "deviceId": "abcdef12-3456-7890",
        "appVersion": "1.2.3+45",
        "hardware": "iPhone 12 Pro",
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
    expect(find.text("Device: abcdef12 | App: 1.2.3+45"), findsOneWidget);
    expect(find.text("Hardware: iPhone 12 Pro"), findsOneWidget);
    expect(loadCount, 1);

    await tester.pumpWidget(buildWidget("Session Active"));
    expect(find.text("Session: Session Active"), findsOneWidget);
    expect(find.text("Loading network info..."), findsNothing);
    expect(
      find.text(
          "Network: Wi-Fi (enable location for SSID) | IP: 192.168.178.20"),
      findsOneWidget,
    );
    expect(find.text("Device: abcdef12 | App: 1.2.3+45"), findsOneWidget);
    expect(find.text("Hardware: iPhone 12 Pro"), findsOneWidget);
    expect(loadCount, 1);
  });

  testWidgets("shows clear identity fallback when diagnostics are unavailable",
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionInfoWidget(
            sessionDisplay: "No active session",
            networkInfoLoader: () async => {
              "networkType": "No Connection",
              "ip": "Unknown IP",
            },
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      find.text("Network: No Connection | IP: Unknown IP"),
      findsOneWidget,
    );
    expect(
      find.text("Device: Unknown device | App: App version unavailable"),
      findsOneWidget,
    );
    expect(find.text("Hardware: Hardware unavailable"), findsOneWidget);
  });

  testWidgets("compact mode can hide diagnostics for tight panes",
      (WidgetTester tester) async {
    var loadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionInfoWidget(
            sessionDisplay: "No active session",
            compact: true,
            showDiagnostics: false,
            networkInfoLoader: () async {
              loadCount += 1;
              return {
                "networkType": "Wi-Fi",
                "ip": "192.168.178.20",
                "deviceId": "abcdef12-3456-7890",
                "appVersion": "1.2.3+45",
                "hardware": "Samsung Galaxy S10e",
              };
            },
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text("Session: No active session"), findsOneWidget);
    expect(find.textContaining("Network:"), findsNothing);
    expect(find.textContaining("Device:"), findsNothing);
    expect(find.textContaining("Hardware:"), findsNothing);
    expect(loadCount, 0);
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
                "deviceId": "session-diagnostics-device-1234567890",
                "appVersion": "2026.6.8+diagnostics-build",
                "hardware": "Samsung Galaxy S10e diagnostic runner",
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
