import "dart:async";
import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:sensors_plus/sensors_plus.dart";

import "../models/capture_context_metadata.dart";
import "log_service.dart";

enum DeviceLevelZone { green, amber, red, unavailable }

class DeviceLevelReading {
  const DeviceLevelReading({
    required this.rollDegrees,
    required this.pitchDegrees,
    required this.capturedAt,
    required this.sensorAvailable,
    this.toleranceDegrees = 5,
  });

  final double? rollDegrees;
  final double? pitchDegrees;
  final DateTime capturedAt;
  final bool sensorAvailable;
  final double toleranceDegrees;

  bool get isLevel {
    final roll = rollDegrees;
    return sensorAvailable && roll != null && roll.abs() <= toleranceDegrees;
  }

  DeviceLevelZone get zone {
    final roll = rollDegrees;
    if (!sensorAvailable || roll == null) {
      return DeviceLevelZone.unavailable;
    }
    final absoluteRoll = roll.abs();
    if (absoluteRoll <= 2) {
      return DeviceLevelZone.green;
    }
    if (absoluteRoll <= toleranceDegrees) {
      return DeviceLevelZone.amber;
    }
    return DeviceLevelZone.red;
  }

  static DeviceLevelReading fromAcceleration({
    required double x,
    required double y,
    required double z,
    required DateTime capturedAt,
    double toleranceDegrees = 5,
  }) {
    final rollDegrees = math.atan2(x, z) * 180 / math.pi;
    final pitchDegrees = math.atan2(y, z) * 180 / math.pi;
    return DeviceLevelReading(
      rollDegrees: rollDegrees,
      pitchDegrees: pitchDegrees,
      capturedAt: capturedAt,
      sensorAvailable: true,
      toleranceDegrees: toleranceDegrees,
    );
  }

  static DeviceLevelReading unavailable({
    DateTime? capturedAt,
    double toleranceDegrees = 5,
  }) {
    return DeviceLevelReading(
      rollDegrees: null,
      pitchDegrees: null,
      capturedAt: capturedAt ?? DateTime.now(),
      sensorAvailable: false,
      toleranceDegrees: toleranceDegrees,
    );
  }

  DeviceLevelMetadata toMetadata() {
    return DeviceLevelMetadata(
      rollDegrees: rollDegrees,
      pitchDegrees: pitchDegrees,
      toleranceDegrees: toleranceDegrees,
      isLevel: isLevel,
      sensorAvailable: sensorAvailable,
      capturedAt: capturedAt,
    );
  }
}

class DeviceLevelService {
  DeviceLevelService({
    Stream<AccelerometerEvent> Function()? accelerometerStreamFactory,
    DateTime Function()? now,
  })  : _accelerometerStreamFactory = accelerometerStreamFactory ??
            (() => accelerometerEventStream(
                  samplingPeriod: SensorInterval.normalInterval,
                )),
        _now = now ?? DateTime.now,
        reading = ValueNotifier<DeviceLevelReading>(
          DeviceLevelReading.unavailable(capturedAt: (now ?? DateTime.now)()),
        );

  final Stream<AccelerometerEvent> Function() _accelerometerStreamFactory;
  final DateTime Function() _now;
  final ValueNotifier<DeviceLevelReading> reading;
  StreamSubscription<AccelerometerEvent>? _subscription;

  void start() {
    if (_subscription != null) {
      return;
    }
    try {
      _subscription = _accelerometerStreamFactory().listen(
        (event) {
          reading.value = DeviceLevelReading.fromAcceleration(
            x: event.x,
            y: event.y,
            z: event.z,
            capturedAt: _now(),
          );
        },
        onError: (Object error) {
          LogService.instance.registerLog("Device level sensor error: $error");
          reading.value = DeviceLevelReading.unavailable(capturedAt: _now());
        },
      );
    } catch (error) {
      LogService.instance
          .registerLog("Device level sensor unavailable: $error");
      reading.value = DeviceLevelReading.unavailable(capturedAt: _now());
    }
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  Future<void> dispose() async {
    await stop();
    reading.dispose();
  }
}
