package com.amaia23.hydracam.court

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * H3: keeps the court runtime alive. Camera + dataSync (+ microphone when granted), START_STICKY,
 * partial wake lock and a high-performance Wi-Fi lock. Must first be started from a visible
 * activity (Android 14+ while-in-use rule for camera).
 */
class CourtCameraService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promote(includeDataSync = true)
        acquireLocks()
        CourtRuntime.get(this).start()
        return START_STICKY
    }

    /** Android 15 dataSync 6 h cap: keep running as camera (+ microphone) only. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        CourtRuntime.get(this).logger.warn(TAG, "FGS timeout for type $fgsType; dropping dataSync.")
        promote(includeDataSync = false)
    }

    override fun onDestroy() {
        CourtRuntime.get(this).onServiceDestroyed()
        wakeLock?.takeIf { it.isHeld }?.release()
        wifiLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        wifiLock = null
        super.onDestroy()
    }

    private fun promote(includeDataSync: Boolean) {
        val notification = buildNotification()
        var types = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            types = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (granted(Manifest.permission.RECORD_AUDIO)) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
        }
        if (includeDataSync && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, types)
        } catch (error: RuntimeException) {
            // Camera not allowed (no permission, or started from the background): keep uploading.
            CourtRuntime.get(this).logger.warn(TAG, "startForeground(types=$types) refused.", error)
            val fallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            try {
                ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, fallback)
            } catch (again: RuntimeException) {
                CourtRuntime.get(this).logger.warn(TAG, "Fallback startForeground refused; stopping.", again)
                stopSelf()
            }
        }
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HydraCamCourt:runtime").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "HydraCamCourt:wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Court camera", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, CourtActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("HydraCam Court")
            .setContentText("Camera service running")
            .setOngoing(true)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "CourtService"
        private const val CHANNEL_ID = "court_runtime"
        private const val NOTIFICATION_ID = 2301

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, CourtCameraService::class.java))
        }
    }
}
