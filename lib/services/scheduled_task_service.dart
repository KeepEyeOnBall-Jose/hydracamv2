import "dart:async";

typedef ScheduledTaskCallback = FutureOr<void> Function();

/// Service for managing scheduled tasks.
class ScheduledTaskService {
  static final ScheduledTaskService _instance = ScheduledTaskService();

  final Map<String, _ScheduledTaskEntry> _tasks = {};
  final DateTime Function() _now;
  Duration _clockOffset = Duration.zero;

  ScheduledTaskService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static ScheduledTaskService get instance => _instance;

  Duration get clockOffset => _clockOffset;

  DateTime correctedNow() => _now().add(_clockOffset);

  void updateClockOffset(Duration offset) {
    _clockOffset = offset;
  }

  Duration delayUntil(DateTime scheduledTime) {
    return scheduledTime.difference(correctedNow());
  }

  /// Schedules a task to execute a callback at a specific time.
  Future<void> scheduleTask(
      String taskId, DateTime scheduledTime, ScheduledTaskCallback callback) {
    final Duration delay = delayUntil(scheduledTime);
    // Cancel existing task with the same ID
    _cancelScheduledTask(taskId);

    if (delay.isNegative) {
      return Future<void>.sync(callback);
    }

    final completer = Completer<void>();

    // Schedule the new task
    final timer = Timer(delay, () async {
      try {
        await callback();
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _tasks.remove(taskId); // Remove the task after execution
      }
    });
    _tasks[taskId] = _ScheduledTaskEntry(timer, completer);
    return completer.future;
  }

  /// Cancels a task by its ID.
  void cancelTask(String taskId) {
    _cancelScheduledTask(taskId);
  }

  /// Checks if a task with the given ID is scheduled.
  bool isTaskScheduled(String taskId) => _tasks.containsKey(taskId);

  void _cancelScheduledTask(String taskId) {
    final task = _tasks.remove(taskId);
    if (task == null) {
      return;
    }
    task.timer.cancel();
    if (!task.completer.isCompleted) {
      task.completer.complete();
    }
  }
}

class _ScheduledTaskEntry {
  final Timer timer;
  final Completer<void> completer;

  const _ScheduledTaskEntry(this.timer, this.completer);
}
