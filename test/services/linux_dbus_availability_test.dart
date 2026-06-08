import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/linux_dbus_availability.dart";

void main() {
  group("Linux DBus availability", () {
    test("skips system-bus plugins only on linux without system bus", () {
      expect(
        LinuxDbusAvailability.shouldSkipSystemBusPluginsForTesting(
          isLinux: true,
          hasSystemBusSocket: false,
        ),
        isTrue,
      );
      expect(
        LinuxDbusAvailability.shouldSkipSystemBusPluginsForTesting(
          isLinux: true,
          hasSystemBusSocket: true,
        ),
        isFalse,
      );
      expect(
        LinuxDbusAvailability.shouldSkipSystemBusPluginsForTesting(
          isLinux: false,
          hasSystemBusSocket: false,
        ),
        isFalse,
      );
    });

    test("uses DBus session path when provided", () {
      expect(
        LinuxDbusAvailability.shouldSkipSessionBusPluginsForTesting(
          isLinux: true,
          sessionBusAddress: "unix:path=/tmp/missing-bus",
          xdgRuntimeDir: null,
          fileExists: (_) => false,
        ),
        isTrue,
      );
      expect(
        LinuxDbusAvailability.shouldSkipSessionBusPluginsForTesting(
          isLinux: true,
          sessionBusAddress: "unix:path=/tmp/live-bus",
          xdgRuntimeDir: null,
          fileExists: (_) => true,
        ),
        isFalse,
      );
    });

    test("falls back to XDG runtime bus path", () {
      final checkedPaths = <String>[];

      final shouldSkip =
          LinuxDbusAvailability.shouldSkipSessionBusPluginsForTesting(
        isLinux: true,
        sessionBusAddress: null,
        xdgRuntimeDir: "/run/user/1000",
        fileExists: (path) {
          checkedPaths.add(path);
          return false;
        },
      );

      expect(shouldSkip, isTrue);
      expect(checkedPaths, ["/run/user/1000/bus"]);
    });
  });
}
