import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import android_power_monitor as monitor


class AndroidPowerMonitorTest(unittest.TestCase):
    def test_parse_dumpsys_battery_keeps_samsung_current_now(self) -> None:
        parsed = monitor.parse_dumpsys_battery(
            """
            Current Battery Service state:
              USB powered: true
              level: 37
              voltage: 3761
              temperature: 387
              current now: 52
            """
        )

        self.assertEqual(parsed["usb_powered"], True)
        self.assertEqual(parsed["level"], 37)
        self.assertEqual(parsed["voltage"], 3761)
        self.assertEqual(parsed["temperature"], 387)
        self.assertEqual(parsed["current_now"], 52)

    def test_cpu_percentages_are_core_normalized(self) -> None:
        previous = monitor.CpuSnapshot(
            total_ticks=1000,
            cpu_count=4,
            process_ticks=100,
        )
        current = monitor.CpuSnapshot(
            total_ticks=1400,
            cpu_count=4,
            process_ticks=120,
        )

        percentages = monitor.cpu_percentages(previous, current)

        self.assertIsNotNone(percentages)
        self.assertAlmostEqual(percentages["app_cpu_total_pct"], 5.0)
        self.assertAlmostEqual(percentages["app_cpu_core_pct"], 20.0)

    def test_proc_pid_stat_parses_names_with_spaces(self) -> None:
        output = (
            "32433 (maia23.hydracam) S 536 536 0 0 -1 0 0 0 0 0 "
            "928 121 0 0 10 -10 41"
        )

        self.assertEqual(monitor.parse_proc_pid_stat(output), 1049)


if __name__ == "__main__":
    unittest.main()
