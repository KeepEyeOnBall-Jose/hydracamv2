import "package:flutter/foundation.dart";

// ignore: avoid_classes_with_only_static_members
class LinuxDbusAvailability {
  static const String systemBusSocketPath = "/var/run/dbus/system_bus_socket";

  static bool get shouldSkipSystemBusPlugins => false;

  static bool get shouldSkipSessionBusPlugins => false;

  static bool shouldSkipSystemBusPluginsFor({
    required bool isLinux,
    required bool hasSystemBusSocket,
  }) {
    return isLinux && !hasSystemBusSocket;
  }

  @visibleForTesting
  static bool shouldSkipSystemBusPluginsForTesting({
    required bool isLinux,
    required bool hasSystemBusSocket,
  }) {
    return shouldSkipSystemBusPluginsFor(
      isLinux: isLinux,
      hasSystemBusSocket: hasSystemBusSocket,
    );
  }

  @visibleForTesting
  static bool shouldSkipSessionBusPluginsForTesting({
    required bool isLinux,
    required String? sessionBusAddress,
    required String? xdgRuntimeDir,
    required bool Function(String path) fileExists,
  }) {
    if (!isLinux) {
      return false;
    }

    if (sessionBusAddress != null &&
        sessionBusAddress.startsWith("unix:path=")) {
      return !fileExists(sessionBusAddress.substring("unix:path=".length));
    }
    if (sessionBusAddress != null && sessionBusAddress.isNotEmpty) {
      return false;
    }

    if (xdgRuntimeDir != null && xdgRuntimeDir.isNotEmpty) {
      return !fileExists("$xdgRuntimeDir/bus");
    }

    return true;
  }
}
