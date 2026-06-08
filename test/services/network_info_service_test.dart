import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/network_info_service.dart";

void main() {
  group("Network type labels", () {
    test("describes Wi-Fi with unavailable SSID explicitly", () {
      expect(
        NetworkInfoService.formatNetworkType(
          const [ConnectivityResult.wifi],
        ),
        "Wi-Fi (enable location for SSID)",
      );
    });

    test("includes SSID when the platform exposes it", () {
      expect(
        NetworkInfoService.formatNetworkType(
          const [ConnectivityResult.wifi],
          ssid: "HydraCam Lab",
        ),
        "Wi-Fi (HydraCam Lab)",
      );
    });

    test("describes pending connected-device network status", () {
      expect(
        ConnectedDeviceNetworkStatus.unknown.label,
        "Network details pending",
      );
    });

    test("describes unavailable SSID as a location requirement", () {
      expect(
        NetworkInfoService.formatSsidLabel(
          const NetworkSnapshot(
            isWifiActive: true,
            source: "test",
          ),
        ),
        "Enable location for SSID",
      );
    });
  });
}
