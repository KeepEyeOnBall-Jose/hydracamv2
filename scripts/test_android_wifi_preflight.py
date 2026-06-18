import ipaddress
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import android_wifi_preflight as preflight


class AndroidWifiPreflightTest(unittest.TestCase):
    def test_extract_wlan0_ip_from_route_output(self) -> None:
        self.assertEqual(
            preflight.extract_wlan0_ip(
                "10.10.100.0/22 dev wlan0 proto kernel scope link "
                "src 10.10.102.250"
            ),
            "10.10.102.250",
        )

    def test_parse_route_interface_from_macos_route_output(self) -> None:
        self.assertEqual(
            preflight.parse_route_interface(
                """
   route to: 10.10.103.208
destination: 10.10.103.208
  interface: en0
"""
            ),
            "en0",
        )

    def test_parse_ifconfig_ipv4_network_from_macos_hex_netmask(self) -> None:
        network = preflight.parse_ifconfig_ipv4_network(
            """
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        inet 10.10.103.203 netmask 0xfffffc00 broadcast 10.10.103.255
"""
        )

        self.assertEqual(network, ipaddress.ip_network("10.10.100.0/22"))

    def test_parse_ifconfig_ipv4_network_from_dotted_netmask(self) -> None:
        network = preflight.parse_ifconfig_ipv4_network(
            """
wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
        inet 192.168.50.42 netmask 255.255.255.0 broadcast 192.168.50.255
"""
        )

        self.assertEqual(network, ipaddress.ip_network("192.168.50.0/24"))

    def test_resolve_expected_subnet_keeps_literal_subnet(self) -> None:
        self.assertEqual(
            preflight.resolve_expected_subnet("172.16.4.0/23", "1.1.1.1", 1),
            ipaddress.ip_network("172.16.4.0/23"),
        )


if __name__ == "__main__":
    unittest.main()
