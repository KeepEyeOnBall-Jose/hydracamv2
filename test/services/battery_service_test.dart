import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/battery_service.dart";

void main() {
  testWidgets("BatteryService shows warning when battery level is low", (tester) async {
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
}
