import 'package:flutter/material.dart';

class DeviceIdProvider extends ChangeNotifier {
  String _deviceId;

  DeviceIdProvider(this._deviceId);

  String get deviceId => _deviceId;

  void setDeviceId(String newDeviceId) {
    _deviceId = newDeviceId;
    notifyListeners();
  }
}
