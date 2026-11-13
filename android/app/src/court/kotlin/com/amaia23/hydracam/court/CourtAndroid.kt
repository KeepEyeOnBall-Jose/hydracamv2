package com.amaia23.hydracam.court

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.ToneGenerator
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.IOException
import java.io.InputStream
import java.security.KeyStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** logcat + a small ring buffer the status screen shows. */
class AndroidCourtLogger(private val capacity: Int = 80) : CourtLogger {
    private val lines = ArrayDeque<String>()
    private val format = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    override fun info(tag: String, message: String) {
        Log.i(tag, message)
        remember("I", tag, message)
    }

    override fun warn(tag: String, message: String, error: Throwable?) {
        Log.w(tag, message, error)
        remember("W", tag, if (error == null) message else "$message (${error.javaClass.simpleName}: ${error.message})")
    }

    @Synchronized
    fun recent(): List<String> = lines.toList()

    @Synchronized
    private fun remember(level: String, tag: String, message: String) {
        lines.addLast("${format.format(Date())} $level $tag: $message")
        while (lines.size > capacity) {
            lines.removeFirst()
        }
    }
}

/** `su -c` with a hard timeout. The first call on a Magisk phone shows a grant prompt. */
object RootShell {
    data class Result(val exitCode: Int, val output: String)

    fun run(command: String, timeoutMs: Long = 8_000): Result? {
        val process = start(command) ?: return null
        val deadline = System.currentTimeMillis() + timeoutMs
        while (true) {
            exitCodeOrNull(process)?.let { return Result(it, readAll(process.inputStream)) }
            if (System.currentTimeMillis() >= deadline) {
                break
            }
            Thread.sleep(POLL_MS)
        }
        process.destroy()
        return null
    }

    private fun start(command: String): Process? = try {
        Runtime.getRuntime().exec(arrayOf("su", "-c", command))
    } catch (ignored: IOException) {
        null
    } catch (ignored: SecurityException) {
        null
    }

    /** null while [process] is still running. */
    private fun exitCodeOrNull(process: Process): Int? = try {
        process.exitValue()
    } catch (ignored: IllegalThreadStateException) {
        null
    }

    fun isRooted(): Boolean = run("id")?.let { it.exitCode == 0 && it.output.contains("uid=0") } == true

    fun startActivity(component: String): Boolean = run("am start -n $component")?.exitCode == 0

    fun grant(packageName: String, permission: String): Boolean =
        run("pm grant $packageName $permission")?.exitCode == 0

    private fun readAll(stream: InputStream): String = stream.bufferedReader().use { it.readText() }

    private const val POLL_MS = 50L
}

/** Battery, thermal, storage and Wi-Fi for C1 `state`; caps for `hello`. */
class DeviceStatusProbe(private val context: Context) {
    data class Battery(val pct: Int, val charging: Boolean, val tempC: Double)

    fun battery(): Battery {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return Battery(-1, false, 0.0)
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, PERCENT)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val temp = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
        val pct = if (level >= 0 && scale > 0) level * PERCENT / scale else -1
        return Battery(pct, plugged != 0, temp / TENTHS_PER_DEGREE)
    }

    /** PowerManager thermal status (0 = none … 6 = shutdown); 0 below API 29. */
    fun thermal(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return 0
        }
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.currentThermalStatus
    }

    fun freeBytes(): Long = StatFs(context.filesDir.path).availableBytes

    @Suppress("DEPRECATION")
    fun wifiRssi(): Int {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return 0
        return try {
            wifi.connectionInfo?.rssi ?: 0
        } catch (ignored: SecurityException) {
            0
        }
    }

    /** Samsung "Protect battery" caps charging at 85 %; other phones report 100. */
    fun chargeCapPct(): Int {
        val resolver = context.contentResolver
        val protect = listOf(
            { Settings.Global.getInt(resolver, SAMSUNG_PROTECT_BATTERY, 0) },
            { Settings.System.getInt(resolver, SAMSUNG_PROTECT_BATTERY, 0) },
        ).any { read -> runCatching(read).getOrDefault(0) == 1 }
        return if (protect) SAMSUNG_PROTECT_CAP_PCT else PERCENT
    }

    fun caps(): CourtCaps {
        var maxRes = "720p"
        var fps = listOf(BASE_FPS)
        var torch = false
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val characteristics = manager.getCameraCharacteristics(CourtCameraRecorder.backCameraId(manager))
            val sizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(MediaCodec::class.java)
                .orEmpty()
            val widest = sizes.maxOfOrNull { it.width } ?: 0
            maxRes = RecordProfile.resFor(widest)
            val ranges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES).orEmpty()
            // Promise only what record.prepare accepts (C1 1.16 nacks any other fps `unsupported`).
            fps = CapturePlanner.recordableFps(ranges.map { it.lower..it.upper }, listOf(BASE_FPS, HIGH_FPS))
                .ifEmpty { listOf(BASE_FPS) }
            torch = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } catch (error: Exception) {
            Log.w(TAG, "Camera caps unavailable.", error)
        }
        val hevc = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, ignoreCase = true) }
        }
        val speaker = context.packageManager.hasSystemFeature(PackageManager.FEATURE_AUDIO_OUTPUT)
        return CourtCaps(maxRes = maxRes, fps = fps, hevc = hevc, encoders = 2, torch = torch, speaker = speaker)
    }

    private companion object {
        const val TAG = "CourtProbe"
        const val SAMSUNG_PROTECT_BATTERY = "protect_battery"

        /** Samsung "Protect battery" stops charging at 85 %. */
        const val SAMSUNG_PROTECT_CAP_PCT = 85
        const val PERCENT = 100
        const val TENTHS_PER_DEGREE = 10.0
        const val BASE_FPS = 30
        const val HIGH_FPS = 60
    }
}

/** H2: the enrollment (including the device secret) encrypted with an Android Keystore AES-GCM key. */
class KeystoreCredentialStore(context: Context, private val logger: CourtLogger) : CredentialStore {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    override fun load(): CourtEnrollment? {
        val iv = prefs.getString(KEY_IV, null) ?: return null
        val ciphertext = prefs.getString(KEY_CIPHERTEXT, null) ?: return null
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(GCM_TAG_BITS, Base64.decode(iv, Base64.NO_WRAP)))
            val plain = cipher.doFinal(Base64.decode(ciphertext, Base64.NO_WRAP))
            CourtEnrollment.fromJson(JSONObject(String(plain, Charsets.UTF_8)))
        } catch (error: Exception) {
            logger.warn(TAG, "Stored enrollment unreadable; clearing it.", error)
            clear()
            null
        }
    }

    @Synchronized
    override fun save(enrollment: CourtEnrollment) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ciphertext = cipher.doFinal(enrollment.toJson().toString().toByteArray(Charsets.UTF_8))
        prefs.edit()
            .putString(KEY_IV, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString(KEY_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .commit()
    }

    @Synchronized
    override fun clear() {
        prefs.edit().clear().commit()
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(AES_KEY_BITS)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "CourtCredentials"
        const val PREFS = "court_credentials"
        const val KEY_IV = "iv"
        const val KEY_CIPHERTEXT = "ciphertext"
        const val KEY_ALIAS = "hydracam_court_enrollment"
        const val AES_KEY_BITS = 256
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
    }
}

/** The recording session id survives a process death so `hello.activeSessionId` can report it. */
class PrefsActiveSessionStore(context: Context) : ActiveSessionStore {
    private val prefs = context.applicationContext.getSharedPreferences("court_runtime", Context.MODE_PRIVATE)

    override fun load(): String? = prefs.getString(KEY, null)

    override fun save(sessionId: String?) {
        val editor = prefs.edit()
        if (sessionId == null) editor.remove(KEY) else editor.putString(KEY, sessionId)
        editor.commit()
    }

    private companion object {
        const val KEY = "activeSessionId"
    }
}

/** Last `upload.policy` (R10), so maxKbps and keepDays survive a restart before K2 re-sends it. */
class PrefsUploadPolicyStore(context: Context, private val logger: CourtLogger) : UploadPolicyStore {
    private val prefs = context.applicationContext.getSharedPreferences("court_runtime", Context.MODE_PRIVATE)

    override fun load(): UploadPolicy {
        val text = prefs.getString(KEY, null) ?: return UploadPolicy.DEFAULT
        return try {
            UploadPolicy.fromJson(JSONObject(text))
        } catch (error: Exception) {
            logger.warn(TAG, "Stored upload policy is invalid; using the default.", error)
            UploadPolicy.DEFAULT
        }
    }

    override fun save(policy: UploadPolicy) {
        prefs.edit().putString(KEY, policy.toJson().toString()).commit()
    }

    private companion object {
        const val KEY = "uploadPolicy"
        const val TAG = "CourtPolicy"
    }
}

/** C6 tones through ToneGenerator on the alarm stream (audible even with media muted). */
class ToneGeneratorPlayer(private val logger: CourtLogger) : TonePlayer {
    private var generator: ToneGenerator? = null

    @Synchronized
    override fun play(tone: SignalTone, durationMs: Int) {
        val player = generator ?: try {
            ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME).also { generator = it }
        } catch (error: RuntimeException) {
            logger.warn(TAG, "ToneGenerator unavailable.", error)
            return
        }
        val type = when (tone) {
            SignalTone.HIGH -> ToneGenerator.TONE_CDMA_HIGH_L
            SignalTone.MID -> ToneGenerator.TONE_CDMA_MED_L
            SignalTone.LOW -> ToneGenerator.TONE_CDMA_LOW_L
        }
        player.startTone(type, durationMs)
    }

    private companion object {
        const val TAG = "CourtTones"
    }
}
