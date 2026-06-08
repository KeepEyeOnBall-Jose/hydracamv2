import "dart:io";

import "package:flutter/foundation.dart";

// ignore: avoid_classes_with_only_static_members
class LinuxDbusAvailability {
  static const String systemBusSocketPath = "/var/run/dbus/system_bus_socket";

  static bool get shouldSkipSystemBusPlugins {
    return shouldSkipSystemBusPluginsFor(
      isLinux: Platform.isLinux,
      hasSystemBusSocket: File(systemBusSocketPath).existsSync(),
    );
  }

  static bool get shouldSkipSessionBusPlugins {
    return shouldSkipSessionBusPluginsForTesting(
      isLinux: Platform.isLinux,
      sessionBusAddress: Platform.environment["DBUS_SESSION_BUS_ADDRESS"],
      xdgRuntimeDir: Platform.environment["XDG_RUNTIME_DIR"],
      fileExists: (path) => File(path).existsSync(),
    );
  }

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

    final address = sessionBusAddress;
    if (address != null && address.startsWith("unix:path=")) {
      return !fileExists(address.substring("unix:path=".length));
    }
    if (address != null && address.isNotEmpty) {
      return false;
    }

    final runtimeDir = xdgRuntimeDir;
    if (runtimeDir != null && runtimeDir.isNotEmpty) {
      return !fileExists("$runtimeDir/bus");
    }

    return true;
  }
}
