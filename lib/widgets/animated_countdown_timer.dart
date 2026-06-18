import "dart:async";
import "package:flutter/material.dart";

import "../app_theme.dart";

/// AnimatedCountdownTimer - A circular countdown timer widget.
/// Displays an animated number in the center that updates in real-time,
/// along with a circular progress indicator that completes in sync with the timer.
///
/// ### Parameters:
/// - `duration`: The total duration for the countdown (in milliseconds).
/// - `onComplete`: A callback triggered when the countdown reaches zero.
/// - `finalMessage`: The message displayed at the end of the countdown (default is "Go!").
/// - `textStyle`: Custom style for the countdown text (optional).
/// - `finalMessageStyle`: Custom style for the final message text (optional).

class AnimatedCountdownTimer extends StatefulWidget {
  final int duration; // Total duration in milliseconds
  final VoidCallback onComplete; // Callback for when timer completes
  final String finalMessage; // Message to display at the end of the countdown
  final TextStyle? textStyle; // Style for countdown numbers
  final TextStyle? finalMessageStyle; // Style for final message

  const AnimatedCountdownTimer({
    super.key,
    required this.duration,
    required this.onComplete,
    this.finalMessage = "Go!",
    this.textStyle,
    this.finalMessageStyle,
  });

  @override
  AnimatedCountdownTimerState createState() => AnimatedCountdownTimerState();
}

class AnimatedCountdownTimerState extends State<AnimatedCountdownTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  late int _duration;
  late int _remainingTime; // Remaining time in milliseconds
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _duration = widget.duration <= 0 ? 0 : widget.duration;
    _remainingTime = _duration;

    // Initialize animation controller for scaling effect
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    // Define the scale animation (pulsating effect)
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Start the countdown
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startCountdown() {
    if (_duration <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onComplete();
        }
      });
      return;
    }

    const int tickInterval = 10; // Update every 10ms for smoother animations
    _timer =
        Timer.periodic(const Duration(milliseconds: tickInterval), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isComplete = _remainingTime <= tickInterval;
      setState(() {
        _remainingTime = isComplete ? 0 : _remainingTime - tickInterval;
      });
      if (isComplete) {
        timer.cancel();
        widget.onComplete(); // Trigger the callback
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double rawProgress =
        _duration <= 0 ? 0.0 : _remainingTime / _duration;
    final double progress = rawProgress.clamp(0.0, 1.0).toDouble();

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Circular progress indicator
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              color: AppTheme.primaryColor,
              backgroundColor: AppTheme.surfaceAlt,
            ),
          ),

          // Animated scaling text
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              final String displayText = _remainingTime > 0
                  ? (_remainingTime / 1000)
                      .toStringAsFixed(1) // Format seconds with milliseconds
                  : widget.finalMessage;

              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Text(
                  displayText,
                  style: _remainingTime > 0
                      ? (widget.textStyle ??
                          const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            decoration: TextDecoration.none, // Remove underline
                          ))
                      : (widget.finalMessageStyle ??
                          const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentColor,
                            decoration: TextDecoration.none, // Remove underline
                          )),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
