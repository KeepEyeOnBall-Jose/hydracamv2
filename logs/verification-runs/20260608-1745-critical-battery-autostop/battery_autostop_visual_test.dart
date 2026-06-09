// ignore_for_file: invalid_use_of_visible_for_testing_member

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/battery_service.dart";
import "package:hydracam/services/log_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("critical battery snackbar visual proof", (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 300));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      LogService.instance.clearLogs();
    });

    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(
          body: Center(child: Text("HydraCam battery proof harness")),
        ),
      ),
    );

    BatteryService.configureMonitoring(enabled: false);
    final batteryService = BatteryService(
      messengerState: messengerKey.currentState!,
      lowBatteryThreshold: 40,
      criticalBatteryThreshold: 10,
      onCriticalBatteryCallback: (_) {},
    );
    addTearDown(() {
      batteryService.dispose();
      BatteryService.configureMonitoring(enabled: true);
    });

    batteryService.simulateBatteryLevel(8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile("screenshots/critical_battery_snackbar.png"),
    );
  });
}
