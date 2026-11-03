package com.amaia23.hydracam.spike.preview

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle

/**
 * Trampoline for adb: forwards its extras to [SpikeService] and finishes.
 * `--ez stop true` stops the running service. Camera permission is granted with `pm grant` or the prompt.
 */
class SpikeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA, Manifest.permission.POST_NOTIFICATIONS), 1)
            return
        }
        forward()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        forward()
    }

    private fun forward() {
        val service = Intent(this, SpikeService::class.java)
        if (intent.getBooleanExtra("stop", false)) {
            service.action = SpikeService.ACTION_STOP
        } else {
            service.putExtras(SpikeConfig.from(intent).toBundle())
        }
        startForegroundService(service)
        finish()
    }
}
