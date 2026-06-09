import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/scheduled_task_service.dart";

void main() {
  final fixedNow = DateTime.utc(2026, 6, 8, 18, 26);

  test("computes delay from corrected local time", () {
    final service = ScheduledTaskService(now: () => fixedNow);

    service.updateClockOffset(const Duration(seconds: 2));

    expect(service.clockOffset, const Duration(seconds: 2));
    expect(service.correctedNow(), fixedNow.add(const Duration(seconds: 2)));
    expect(
      service.delayUntil(fixedNow.add(const Duration(seconds: 5))),
      const Duration(seconds: 3),
    );
  });

  test("runs scheduled tasks immediately when corrected time has passed", () {
    final service = ScheduledTaskService(now: () => fixedNow)
      ..updateClockOffset(const Duration(seconds: 2));
    var callCount = 0;

    service.scheduleTask(
      "past-task",
      fixedNow.add(const Duration(seconds: 1)),
      () => callCount += 1,
    );

    expect(callCount, 1);
    expect(service.isTaskScheduled("past-task"), isFalse);
  });

  test("past-due async scheduled tasks can be awaited", () async {
    final service = ScheduledTaskService(now: () => fixedNow)
      ..updateClockOffset(const Duration(seconds: 2));
    var completed = false;

    await service.scheduleTask(
      "past-async-task",
      fixedNow.add(const Duration(seconds: 1)),
      () async {
        await Future<void>.delayed(Duration.zero);
        completed = true;
      },
    );

    expect(completed, isTrue);
    expect(service.isTaskScheduled("past-async-task"), isFalse);
  });

  test("keeps future corrected-time tasks cancellable", () {
    final service = ScheduledTaskService(now: () => fixedNow)
      ..updateClockOffset(const Duration(seconds: -2));

    service.scheduleTask(
      "future-task",
      fixedNow.add(const Duration(seconds: 1)),
      () {},
    );

    expect(
      service.delayUntil(fixedNow.add(const Duration(seconds: 1))),
      const Duration(seconds: 3),
    );
    expect(service.isTaskScheduled("future-task"), isTrue);

    service.cancelTask("future-task");

    expect(service.isTaskScheduled("future-task"), isFalse);
  });

  test("cancelled scheduled tasks settle the returned future", () async {
    final service = ScheduledTaskService(now: () => fixedNow)
      ..updateClockOffset(const Duration(seconds: -2));
    var callCount = 0;

    final scheduledTask = service.scheduleTask(
      "future-async-task",
      fixedNow.add(const Duration(seconds: 1)),
      () async {
        callCount += 1;
      },
    );

    expect(service.isTaskScheduled("future-async-task"), isTrue);

    service.cancelTask("future-async-task");

    await expectLater(
      scheduledTask.timeout(const Duration(milliseconds: 10)),
      completes,
    );
    expect(callCount, 0);
    expect(service.isTaskScheduled("future-async-task"), isFalse);
  });

  test("past-due replacement cancels same-id pending task", () async {
    final service = ScheduledTaskService(now: () => fixedNow)
      ..updateClockOffset(const Duration(seconds: -2));
    var staleCallCount = 0;
    var replacementCallCount = 0;

    final staleTask = service.scheduleTask(
      "replace-task",
      fixedNow.add(const Duration(seconds: 1)),
      () {
        staleCallCount += 1;
      },
    );

    expect(service.isTaskScheduled("replace-task"), isTrue);

    service.updateClockOffset(const Duration(seconds: 2));
    await service.scheduleTask(
      "replace-task",
      fixedNow.add(const Duration(seconds: 1)),
      () {
        replacementCallCount += 1;
      },
    );

    await expectLater(
      staleTask.timeout(const Duration(milliseconds: 10)),
      completes,
    );
    expect(staleCallCount, 0);
    expect(replacementCallCount, 1);
    expect(service.isTaskScheduled("replace-task"), isFalse);
  });
}
