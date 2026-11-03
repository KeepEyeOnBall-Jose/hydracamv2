package com.amaia23.hydracam.court

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Boot / app update. Android 15 forbids camera, microphone and dataSync FGS from BOOT_COMPLETED,
 * so on a rooted phone the activity is launched with `am start` and it starts the service;
 * without root the service start is attempted and may be refused.
 */
class CourtBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        val pending = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                val component = "${appContext.packageName}/${CourtActivity::class.java.name}"
                if (!RootShell.startActivity(component)) {
                    CourtCameraService.start(appContext)
                }
            } catch (error: RuntimeException) {
                CourtRuntime.get(appContext).logger.warn(TAG, "Boot start failed.", error)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private companion object {
        const val TAG = "CourtBoot"
    }
}

/**
 * Scripted manual enrollment (H2), not exported:
 * `su -c am broadcast -n <pkg>/com.amaia23.hydracam.court.CourtEnrollReceiver
 *   -a com.amaia23.hydracam.court.ENROLL --es k2Url … --es deviceId … --es secret …
 *   --es courtId … --es slot … --ei mountRev 0`.
 * The secret is never logged; the result data is `ok` or the validation error.
 * Only root can reach it, so unlike the screen it does not ask for the current secret.
 */
class CourtEnrollReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                val runtime = CourtRuntime.get(appContext)
                val error = when (intent.action) {
                    ACTION_ENROLL -> runtime.enroll(
                        mapOf(
                            "k2Url" to intent.getStringExtra("k2Url"),
                            "deviceId" to intent.getStringExtra("deviceId"),
                            "secret" to intent.getStringExtra("secret"),
                            "courtId" to intent.getStringExtra("courtId"),
                            "slot" to intent.getStringExtra("slot"),
                            "mountRev" to intent.getIntExtra("mountRev", 0),
                        ),
                        checkCurrentSecret = false,
                    )
                    ACTION_CLEAR -> runtime.clearEnrollment(currentSecret = null, checkCurrentSecret = false)
                    else -> "unknown action"
                }
                pending.setResult(
                    if (error ==
                        null
                    ) {
                        Activity.RESULT_OK
                    } else {
                        Activity.RESULT_CANCELED
                    },
                    error ?: "ok",
                    null,
                )
            } catch (error: RuntimeException) {
                pending.setResult(Activity.RESULT_CANCELED, error.javaClass.simpleName, null)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private companion object {
        const val ACTION_ENROLL = "com.amaia23.hydracam.court.ENROLL"
        const val ACTION_CLEAR = "com.amaia23.hydracam.court.CLEAR"
    }
}
