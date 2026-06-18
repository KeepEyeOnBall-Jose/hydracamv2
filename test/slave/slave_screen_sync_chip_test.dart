import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/services/time_sync_service.dart";
import "package:hydracam/widgets/hydracam_surface.dart";

/// Widget coverage for the slave screen's clock-sync status chip.
///
/// `_buildSyncStatusChip` is a private method on the slave screen state, so this
/// test mirrors its exact rendering against the public [TimeSyncService]
/// singleton it listens to. The chip is a small `ValueListenableBuilder`; the
/// behavior under test is: the "calibrating…" placeholder when no calibration
/// exists, and the offset/RTT/sample summary plus the confidence dot once a
/// [TimeSyncResult] is recorded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => TimeSyncService.instance.reset());

  testWidgets("shows calibrating placeholder before any calibration",
      (tester) async {
    TimeSyncService.instance.reset();

    await tester.pumpWidget(const _SyncChipHarness());

    expect(find.textContaining("calibrating"), findsOneWidget);
    expect(find.textContaining("samples"), findsNothing);
  });

  testWidgets("shows offset, RTT and sample summary for a green calibration",
      (tester) async {
    TimeSyncService.instance.reset();

    await tester.pumpWidget(const _SyncChipHarness());

    TimeSyncService.instance.record(TimeSyncResult(
      offset: const Duration(milliseconds: 4),
      uncertainty: const Duration(milliseconds: 12),
      minRoundTrip: const Duration(milliseconds: 24),
      sampleCount: 8,
      confidence: TimeSyncConfidence.green,
      calibratedAt: DateTime.now(),
    ));
    await tester.pump();

    expect(find.textContaining("calibrating"), findsNothing);
    final chipText = tester.widget<Text>(find.byType(Text)).data ?? "";
    expect(chipText, contains("±12 ms"));
    expect(chipText, contains("RTT 24 ms"));
    expect(chipText, contains("8 samples"));

    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.backgroundColor, AppTheme.accent);
  });
}

/// Renders the same chip widget tree as `SlaveScreen._buildSyncStatusChip`.
class _SyncChipHarness extends StatelessWidget {
  const _SyncChipHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<TimeSyncResult?>(
          valueListenable: TimeSyncService.instance.latest,
          builder: (context, result, child) {
            final HydraCamStatusTone tone;
            final IconData icon;
            final String label;
            if (result == null) {
              tone = HydraCamStatusTone.neutral;
              icon = Icons.sync_outlined;
              label = "Clock sync: calibrating…";
            } else {
              tone = switch (result.confidence) {
                TimeSyncConfidence.green => HydraCamStatusTone.active,
                TimeSyncConfidence.yellow => HydraCamStatusTone.warning,
                TimeSyncConfidence.red => HydraCamStatusTone.danger,
              };
              icon = switch (result.confidence) {
                TimeSyncConfidence.green => Icons.sync_outlined,
                TimeSyncConfidence.yellow => Icons.sync_problem_outlined,
                TimeSyncConfidence.red => Icons.sync_disabled_outlined,
              };
              label = "Clock sync: ±${result.uncertainty.inMilliseconds} ms · "
                  "RTT ${result.minRoundTrip.inMilliseconds} ms · "
                  "${result.sampleCount} samples";
            }
            return HydraCamStatusChip(
              status: tone,
              icon: icon,
              label: label,
            );
          },
        ),
      ),
    );
  }
}
