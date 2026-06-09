import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/master/master_announcer.dart";

class FakePeriodicTimer implements Timer {
  FakePeriodicTimer(this.callback);

  final void Function(Timer timer) callback;
  bool _isActive = true;
  int _tick = 0;

  void fire() {
    if (!_isActive) {
      return;
    }
    _tick += 1;
    callback(this);
  }

  @override
  void cancel() {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;
}

Future<void> _flushAsyncBroadcast() => Future<void>.delayed(Duration.zero);

void main() {
  test("starts periodic discovery without real UDP and cancels on stop",
      () async {
    final broadcasts = <String>[];
    FakePeriodicTimer? timer;

    final announcer = MasterAnnouncer(
      broadcastSender: (message, port) {
        broadcasts.add("$message:$port");
      },
      timerFactory: (interval, callback) {
        expect(interval, const Duration(seconds: 2));
        timer = FakePeriodicTimer(callback);
        return timer!;
      },
    );

    announcer.startBroadcasting();

    expect(broadcasts, isEmpty);
    expect(timer, isNotNull);

    timer!.fire();
    await _flushAsyncBroadcast();

    expect(broadcasts, ["MASTER_DISCOVERY:${MasterAnnouncer.broadcastPort}"]);

    announcer.stopBroadcasting();
    expect(timer!.isActive, isFalse);

    timer!.fire();
    await _flushAsyncBroadcast();

    expect(broadcasts, hasLength(1));
  });

  test("broadcast errors do not stop later timer ticks", () async {
    FakePeriodicTimer? timer;
    var attempts = 0;

    final announcer = MasterAnnouncer(
      broadcastSender: (message, port) {
        attempts += 1;
        if (attempts == 1) {
          throw StateError("transient UDP failure");
        }
      },
      timerFactory: (interval, callback) {
        timer = FakePeriodicTimer(callback);
        return timer!;
      },
    );

    announcer.startBroadcasting();
    timer!.fire();
    await _flushAsyncBroadcast();

    timer!.fire();
    await _flushAsyncBroadcast();

    expect(attempts, 2);

    announcer.stopBroadcasting();
  });
}
