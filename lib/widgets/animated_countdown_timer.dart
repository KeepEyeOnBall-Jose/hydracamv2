import 'package:flutter/material.dart';

/// AnimatedCountdownTimer - A reusable countdown timer widget with animations.
///
/// This widget displays an animated countdown timer, starting from a given
/// number of seconds and counting down to zero. Each number is animated,
/// and there's an optional message displayed when the countdown ends.
class AnimatedCountdownTimer extends StatefulWidget {
  final int seconds; // Total seconds for the countdown
  final String endMessage; // Message to display when the countdown ends
  final VoidCallback? onComplete; // Callback when the timer completes

  const AnimatedCountdownTimer({
    Key? key,
    required this.seconds,
    this.endMessage = "Go!",
    this.onComplete,
  }) : super(key: key);

  @override
  _AnimatedCountdownTimerState createState() => _AnimatedCountdownTimerState();
}

class _AnimatedCountdownTimerState extends State<AnimatedCountdownTimer>
    with SingleTickerProviderStateMixin {
  late int _currentSecond; // Current second displayed
  late AnimationController _controller; // Controller for animations
  late Animation<double> _scaleAnimation; // Animation for scaling the number

  @override
  void initState() {
    super.initState();

    // Initialize the current second with the total seconds
    _currentSecond = widget.seconds;

    // Create an AnimationController for the scaling effect
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // Half-second animation
    );

    // Define the scaling animation (from small to large)
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Start the countdown
    _startCountdown();
  }

  void _startCountdown() async {
    for (int i = widget.seconds; i >= 0; i--) {
      // Start the scale animation
      await _controller.forward();
      _controller.reset();

      // Wait for 1 second before updating the number
      if (i > 0) {
        await Future.delayed(const Duration(seconds: 1));
      }

      // Update the current second
      if (mounted) {
        setState(() {
          _currentSecond = i;
        });
      }
    }

    // Execute the onComplete callback if provided
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentSecond > 0) ...[
            // Display the animated number
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Text(
                    '$_currentSecond',
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                );
              },
            ),
            // Loading indicator for each second
            const SizedBox(height: 10),
            const CircularProgressIndicator(),
          ] else ...[
            // Display the final message
            Text(
              widget.endMessage,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
