package com.amaia23.hydracam.spike.preview

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import java.io.File

/** Process CPU (from /proc/self/stat), battery temperature and thermal state. */
class DeviceStats(private val context: Context) {
    private val cores = Runtime.getRuntime().availableProcessors()
    private var lastTicks = -1L
    private var lastAtMs = 0L

    fun sample(): Map<String, Any?> {
        val ticks = processTicks()
        val now = SystemClock.elapsedRealtime()
        // CLK_TCK is 100 on Android.
        val corePct = if (lastTicks >= 0 && now > lastAtMs) (ticks - lastTicks) * 10.0 * 100 / (now - lastAtMs) else null
        lastTicks = ticks
        lastAtMs = now
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val power = context.getSystemService(PowerManager::class.java)
        return mapOf(
            // 100 = one full core.
            "procCpuCorePct" to corePct?.let { Math.round(it * 10) / 10.0 },
            "procCpuDevicePct" to corePct?.let { Math.round(it / cores * 10) / 10.0 },
            "batteryTempC" to battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?.takeIf { it != Int.MIN_VALUE }?.let { it / 10.0 },
            "batteryPct" to battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
            "plugged" to battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1),
            "thermalStatus" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power.currentThermalStatus else null,
            "thermalHeadroom10s" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                power.getThermalHeadroom(10).takeIf { !it.isNaN() }
            } else null,
        )
    }

    private fun processTicks(): Long = runCatching {
        // Fields after the ")" of comm: utime is field 14, stime 15 (1-based in proc(5)).
        val stat = File("/proc/self/stat").readText()
        val fields = stat.substringAfterLast(')').trim().split(' ')
        fields[11].toLong() + fields[12].toLong()
    }.getOrDefault(0L)
}
