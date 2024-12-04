import 'dart:async';

/// Service for managing scheduled tasks.
class ScheduledTaskService {
  static final ScheduledTaskService _instance = ScheduledTaskService._internal();

  final Map<String, Timer> _tasks = {}; // Stores scheduled tasks by ID

  ScheduledTaskService._internal();

  static ScheduledTaskService get instance => _instance;

  /// Schedules a task to execute a callback at a specific time.
  void scheduleTask(String taskId, DateTime scheduledTime, Function() callback) {
    final Duration delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative) {
      callback();
      return;
    }

    // Cancel existing task with the same ID
    _tasks[taskId]?.cancel();

    // Schedule the new task
    _tasks[taskId] = Timer(delay, () {
      callback();
      _tasks.remove(taskId); // Remove the task after execution
    });
  }

  /// Cancels a task by its ID.
  void cancelTask(String taskId) {
    _tasks[taskId]?.cancel();
    _tasks.remove(taskId);
  }

  /// Checks if a task with the given ID is scheduled.
  bool isTaskScheduled(String taskId) => _tasks.containsKey(taskId);
}
