import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/battery_service.dart";
import "package:hydracam/services/log_service.dart";

void main() {
  setUp(() {
    LogService.instance.clearLogs();
  });

  tearDown(() {
    LogService.instance.clearLogs();
  });

  test("skips linux battery plugin when DBus system bus is missing", () {
    expect(
      BatteryService.shouldSkipBatteryPluginForTesting(
        isLinux: true,
        hasSystemBusSocket: false,
      ),
      isTrue,
    );
    expect(
      BatteryService.shouldSkipBatteryPluginForTesting(
        isLinux: true,
        hasSystemBusSocket: true,
      ),
      isFalse,
    );
  });

  testWidgets("BatteryService shows warning when battery level is low",
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    expect(messengerKey.currentState, isNotNull);

    BatteryService.configureMonitoring(enabled: false);

    final batteryService = BatteryService(
      messengerState: messengerKey.currentState!,
      lowBatteryThreshold: 40,
    );

    addTearDown(() {
      batteryService.dispose();
      BatteryService.configureMonitoring(enabled: true);
    });

    batteryService.simulateBatteryLevel(15);
    await tester.pump();

    expect(find.textContaining("Battery is low"), findsOneWidget);
  });

  testWidgets(
      "BatteryService triggers one autostop when battery becomes critical",
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    BatteryService.configureMonitoring(enabled: false);

    var stopCount = 0;
    final batteryService = BatteryService(
      messengerState: messengerKey.currentState!,
      lowBatteryThreshold: 40,
      criticalBatteryThreshold: 10,
      onCriticalBatteryCallback: (level) {
        stopCount++;
      },
    );

    addTearDown(() {
      batteryService.dispose();
      BatteryService.configureMonitoring(enabled: true);
    });

    batteryService.simulateBatteryLevel(8);
    await tester.pump();

    expect(stopCount, 1);
    expect(
      find.textContaining("Recording stopped due to critical battery"),
      findsOneWidget,
    );
    expect(
      LogService.instance.logs.any((entry) => entry["message"]
          .toString()
          .contains("Critical battery: triggering recording stop at 8%.")),
      isTrue,
    );

    batteryService.simulateBatteryLevel(7);
    await tester.pump();

    expect(stopCount, 1);

    batteryService.simulateBatteryLevel(25);
    await tester.pump();
    batteryService.simulateBatteryLevel(8);
    await tester.pump();

    expect(stopCount, 2);
  });

  testWidgets("BatteryService throttles repeated low-battery warnings",
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    BatteryService.configureMonitoring(enabled: false);

    final batteryService = BatteryService(
      messengerState: messengerKey.currentState!,
      lowBatteryThreshold: 40,
      criticalBatteryThreshold: 10,
    );

    addTearDown(() {
      batteryService.dispose();
      BatteryService.configureMonitoring(enabled: true);
    });

    batteryService.simulateBatteryLevel(25);
    await tester.pump();
    expect(find.textContaining("Battery is low (25%)."), findsOneWidget);

    batteryService.simulateBatteryLevel(25);
    await tester.pump();

    expect(find.textContaining("Battery is low (25%)."), findsOneWidget);
  });
}
