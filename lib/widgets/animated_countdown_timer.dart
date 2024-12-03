import 'dart:async';

import 'package:flutter/material.dart';

/// AnimatedCountdownTimer - A reusable countdown timer widget with animations.
///
/// This widget displays an animated countdown timer, starting from a given
/// number of seconds and counting down to zero. Each number is animated,
/// and there's an optional message displayed when the countdown ends.

class CountdownTimer extends StatefulWidget {
  final DateTime targetTime;
  final VoidCallback? onComplete;

  const CountdownTimer({Key? key, required this.targetTime, this.onComplete}) : super(key: key);

  @override
  _CountdownTimerState createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Timer _timer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemainingTime();
    _startTimer();
  }

  void _updateRemainingTime() {
    setState(() {
      _remainingTime = widget.targetTime.difference(DateTime.now());
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      _updateRemainingTime();
      if (_remainingTime.isNegative || _remainingTime.inMilliseconds == 0) {
        timer.cancel();
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _remainingTime.inSeconds % 60;
    final milliseconds = (_remainingTime.inMilliseconds % 1000) ~/ 100;

    return Text(
      '${seconds > 0 ? seconds.toString() : '0'}.${milliseconds.toString()}',
      style: const TextStyle(fontSize: 48, color: Colors.blue, fontWeight: FontWeight.bold),
    );
  }
}