package com.amaia23.hydracam.spike.preview

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/** Foreground camera service hosting one [SpikeRun] at a time. */
class SpikeService : Service() {
    private val thread = HandlerThread("h8-run").apply { start() }
    private val handler = Handler(thread.looper)
    private var run: SpikeRun? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground()
        if (intent?.action == ACTION_STOP) {
            handler.post { stopRun(); stopSelf() }
            return START_NOT_STICKY
        }
        val config = SpikeConfig.from(intent ?: Intent())
        handler.post {
            stopRun()
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "h8:spike")
                .apply { acquire(6 * 60 * 60 * 1_000L) }
            runCatching { SpikeRun(this, config).also { run = it }.start() }
                .onFailure {
                    Log.e(TAG, "run failed to start", it)
                    stopRun()
                }
            if (config.durationS > 0) {
                handler.postDelayed({ stopRun(); stopSelf() }, config.durationS * 1_000L)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.post { stopRun() }
        thread.quitSafely()
        super.onDestroy()
    }

    private fun stopRun() {
        handler.removeCallbacksAndMessages(null)
        run?.let { r -> runCatching { r.stop() }.onFailure { Log.e(TAG, "stop failed", it) } }
        run = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    private fun goForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "H8 spike", NotificationManager.IMPORTANCE_LOW),
        )
        val notification = Notification.Builder(this, CHANNEL)
            .setContentTitle("H8 preview spike")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_STOP = "com.amaia23.hydracam.spike.preview.STOP"
        private const val CHANNEL = "h8"
        private const val NOTIFICATION_ID = 8
        private const val TAG = "H8Spike"
    }
}
