import "package:flutter/material.dart";

import "../services/device_level_service.dart";

class CameraLevelOverlay extends StatelessWidget {
  const CameraLevelOverlay({
    super.key,
    required this.reading,
    required this.child,
  });

  final DeviceLevelReading reading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor(reading.zone);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(_zoneIcon(reading.zone), color: color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _zoneLabel(reading.zone),
                          style: TextStyle(
                            color: color,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _measurementLabel(reading),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _zoneLabel(DeviceLevelZone zone) {
    return switch (zone) {
      DeviceLevelZone.green => "Level",
      DeviceLevelZone.amber => "Adjust",
      DeviceLevelZone.red => "Tilted",
      DeviceLevelZone.unavailable => "Sensor unavailable",
    };
  }

  static IconData _zoneIcon(DeviceLevelZone zone) {
    return switch (zone) {
      DeviceLevelZone.green => Icons.check_circle,
      DeviceLevelZone.amber => Icons.warning_amber,
      DeviceLevelZone.red => Icons.error,
      DeviceLevelZone.unavailable => Icons.sensors_off,
    };
  }

  static Color _zoneColor(DeviceLevelZone zone) {
    return switch (zone) {
      DeviceLevelZone.green => Colors.green,
      DeviceLevelZone.amber => Colors.amber,
      DeviceLevelZone.red => Colors.red,
      DeviceLevelZone.unavailable => Colors.white70,
    };
  }

  static String _measurementLabel(DeviceLevelReading reading) {
    final roll = reading.rollDegrees;
    final pitch = reading.pitchDegrees;
    if (!reading.sensorAvailable || roll == null || pitch == null) {
      return "Roll unavailable | Pitch unavailable";
    }
    return "Roll ${roll.toStringAsFixed(1)} deg | "
        "Pitch ${pitch.toStringAsFixed(1)} deg";
  }
}
