package com.amaia23.hydracam.court

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.core.content.pm.PackageInfoCompat
import okhttp3.OkHttpClient
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Process-wide court runtime: C1 client, command table, state machine, recorder and the C2
 * upload loop. Owned by [CourtCameraService]; the status screen only reads [status].
 */
class CourtRuntime private constructor(context: Context) {
    private val appContext = context.applicationContext
    val logger = AndroidCourtLogger()

    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .callTimeout(5, TimeUnit.MINUTES)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private val credentials = KeystoreCredentialStore(appContext, logger)

    @Volatile
    private var enrollment: CourtEnrollment? = null

    private val scheduler = Executors.newSingleThreadScheduledExecutor { Thread(it, "CourtRuntime") }
    private val uploadExecutor = Executors.newSingleThreadScheduledExecutor { Thread(it, "CourtUploads") }
    private val probe = DeviceStatusProbe(appContext)
    private val root = RootStatus(logger)
    private val storage = CourtStorage(File(appContext.filesDir, "court"))
    private val database = CourtDatabase.open(appContext)
    private val queue = RoomUploadQueueStore(database)
    private val clockEstimator = ClockOffsetEstimator()
    private val tokens = DeviceTokenClient(http, { enrollment })
    private val uploader = C2Uploader(http, queue, logger = logger)

    private val recorder = CourtCameraRecorder(
        appContext,
        storage,
        queue,
        clockEstimator,
        { slot() },
        RecorderEvents(),
        logger,
    )

    private val stateMachine = CourtStateMachine(
        rooted = { root.rooted },
        recorder = RecorderPort(),
        activeSessions = PrefsActiveSessionStore(appContext),
        logger = logger,
    )

    private val signals = CourtSignalPlayer(
        scheduler,
        clockEstimator,
        recorder,
        ToneGeneratorPlayer(logger),
        JsonlAppender(storage.signalsLog()),
        { slot() },
        logger = logger,
    )

    private val commands = CourtCommandTable(
        handlers = mapOf(
            C1.RECORD_PREPARE to CommandHandler { stateMachine.onPrepare(RecordPrepare.fromJson(it.body)) },
            C1.RECORD_START to CommandHandler { stateMachine.onStart(RecordStart.fromJson(it.body)) },
            C1.RECORD_STOP to CommandHandler { stateMachine.onStop(RecordStop.fromJson(it.body)) },
            C1.SIGNAL_EMIT to CommandHandler { signals.emit(SignalEmit.fromJson(it.body)) },
        ),
        reply = { ws.reply(it) },
        logger = logger,
    )

    private val ws: CourtWsClient = CourtWsClient(
        http = http,
        webSocketUrl = { enrollment?.webSocketUrl },
        tokens = tokens,
        hello = ::helloBody,
        state = ::stateBody,
        outbox = EventOutbox(File(storage.root, "outbox"), logger = logger),
        clockEstimator = clockEstimator,
        onCommand = { commands.dispatch(it) },
        logger = logger,
    )

    private val started = AtomicBoolean(false)
    private val uploadKickPending = AtomicBoolean(false)
    private var uploadWake: ScheduledFuture<*>? = null
    private var maxDurationStop: ScheduledFuture<*>? = null
    private var caps: CourtCaps? = null

    @Volatile
    private var pendingCount = 0

    @Volatile
    private var pendingBytes = 0L

    /** Idempotent. Loads the enrollment, checks root, connects to K2 and starts the upload loop. */
    fun start() {
        if (!started.compareAndSet(false, true)) {
            return
        }
        scheduler.execute {
            enrollment = credentials.load()
            logger.info(TAG, "Starting; enrollment=${enrollment ?: "none"}.")
            checkRoot()
            scheduler.scheduleWithFixedDelay({ checkRoot() }, ROOT_RECHECK_MS, ROOT_RECHECK_MS, TimeUnit.MILLISECONDS)
            ws.start()
        }
        uploadExecutor.execute {
            recoverSidecars()
            drainUploads()
        }
    }

    fun onServiceDestroyed() {
        logger.info(TAG, "Service destroyed; closing the K2 connection.")
        ws.stop()
        started.set(false)
    }

    /** Blocking (Keystore + Room); call off the main thread. Returns an error message or null. */
    fun enroll(values: Map<String, Any?>): String? {
        val candidate = try {
            CourtEnrollment(
                k2Url = values["k2Url"]?.toString().orEmpty().trim(),
                deviceId = values["deviceId"]?.toString().orEmpty().trim(),
                secret = values["secret"]?.toString().orEmpty(),
                courtId = values["courtId"]?.toString().orEmpty().trim(),
                slot = values["slot"]?.toString().orEmpty().trim(),
                mountRev = values["mountRev"]?.toString()?.trim()?.toIntOrNull() ?: 0,
            )
        } catch (error: Exception) {
            return "invalid enrollment"
        }
        CourtEnrollment.validate(candidate)?.let { return it }
        credentials.save(candidate)
        logger.info(TAG, "Enrolled $candidate.")
        applyEnrollment(candidate)
        return null
    }

    fun clearEnrollment() {
        credentials.clear()
        logger.info(TAG, "Enrollment cleared.")
        applyEnrollment(null)
    }

    /** Cached values only: safe on the main thread. */
    fun status(): Map<String, Any?> {
        val current = enrollment
        val estimate = clockEstimator.current()
        val battery = probe.battery()
        val phase = stateMachine.phase
        return mapOf(
            "enrolled" to (current != null),
            "k2Url" to current?.k2Url,
            "deviceId" to current?.deviceId,
            "courtId" to current?.courtId,
            "slot" to current?.slot,
            "mountRev" to current?.mountRev,
            "rooted" to root.rooted,
            "rootCheckedAtMs" to root.checkedAtMs,
            "connected" to ws.isOpen,
            "connectedAtMs" to ws.connectedAtMs,
            "connectError" to ws.lastConnectError,
            "phase" to phase.javaClass.simpleName,
            "mode" to stateMachine.mode(pendingCount > 0).wire,
            "activeSessionId" to stateMachine.activeSessionId,
            "lastError" to stateMachine.lastError,
            "camera" to recorder.cameraState,
            "clockOffsetMs" to estimate?.offsetMs,
            "clockRttMs" to estimate?.rttMs,
            "pendingUploads" to pendingCount,
            "pendingUploadBytes" to pendingBytes,
            "batteryPct" to battery.pct,
            "charging" to battery.charging,
            "tempC" to battery.tempC,
            "thermal" to probe.thermal(),
            "freeBytes" to probe.freeBytes(),
            "logs" to logger.recent(),
        )
    }

    private fun applyEnrollment(value: CourtEnrollment?) {
        enrollment = value
        tokens.invalidate()
        scheduler.execute {
            ws.stop()
            if (started.get() && value != null) {
                ws.start()
            }
        }
    }

    private fun slot(): String = enrollment?.slot.orEmpty()

    private fun checkRoot() {
        root.check { rooted ->
            if (rooted) {
                grantRuntimePermissions()
                // Re-send hello with rooted:true.
                ws.stop()
                ws.start()
            }
        }
    }

    private fun grantRuntimePermissions() {
        val permissions = mutableListOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        for (permission in permissions) {
            if (!RootShell.grant(appContext.packageName, permission)) {
                logger.warn(TAG, "pm grant $permission failed.")
            }
        }
    }

    private fun helloBody(): HelloBody {
        val current = enrollment
        val packageInfo = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
        val deviceCaps = caps ?: probe.caps().also { caps = it }
        return HelloBody(
            deviceId = current?.deviceId.orEmpty(),
            appVersion = packageInfo.versionName.orEmpty(),
            versionCode = PackageInfoCompat.getLongVersionCode(packageInfo),
            model = "${Build.MANUFACTURER} ${Build.MODEL}",
            androidSdk = Build.VERSION.SDK_INT,
            rooted = root.rooted,
            courtId = current?.courtId.orEmpty(),
            slot = current?.slot.orEmpty(),
            mountRev = current?.mountRev ?: 0,
            caps = deviceCaps,
            activeSessionId = stateMachine.activeSessionId,
        )
    }

    private fun stateBody(): StateBody {
        uploadExecutor.execute { refreshPendingCounts() }
        val battery = probe.battery()
        return StateBody(
            mode = stateMachine.mode(pendingCount > 0),
            batteryPct = battery.pct,
            charging = battery.charging,
            chargeCapPct = probe.chargeCapPct(),
            tempC = battery.tempC,
            thermal = probe.thermal(),
            freeBytes = probe.freeBytes(),
            pendingUploadBytes = pendingBytes,
            wifiRssi = probe.wifiRssi(),
            lastError = stateMachine.lastError,
        )
    }

    private fun kickUploads() {
        if (uploadKickPending.compareAndSet(false, true)) {
            uploadExecutor.execute { drainUploads() }
        }
    }

    /** Upload thread only. */
    private fun drainUploads() {
        uploadKickPending.set(false)
        var delayMs = UPLOAD_IDLE_MS
        try {
            var rounds = 0
            while (rounds < UPLOAD_BATCH && uploader.runOnce()) {
                rounds += 1
            }
            refreshPendingCounts()
            delayMs = if (rounds >= UPLOAD_BATCH) {
                0
            } else {
                val wakeAt = queue.nextWakeAtMs()
                if (wakeAt == null) UPLOAD_IDLE_MS else wakeAt - System.currentTimeMillis()
            }
        } catch (error: Exception) {
            logger.warn(TAG, "Upload loop failed.", error)
        }
        uploadWake?.cancel(false)
        uploadWake = uploadExecutor.schedule(
            { kickUploads() },
            delayMs.coerceIn(UPLOAD_MIN_DELAY_MS, UPLOAD_IDLE_MS),
            TimeUnit.MILLISECONDS,
        )
    }

    /** Upload thread only. */
    private fun refreshPendingCounts() {
        pendingCount = queue.activeCount()
        pendingBytes = queue.activeBytes()
    }

    /** Re-enqueues sidecar segments missing from the queue (process died between the two writes). */
    private fun recoverSidecars() {
        val sessionsDir = File(storage.root, "sessions")
        val dirs = sessionsDir.listFiles()?.filter { it.isDirectory }.orEmpty()
        var recovered = 0
        for (dir in dirs) {
            val sidecar = File(dir, "segments.jsonl")
            if (!sidecar.isFile) {
                continue
            }
            sidecar.forEachLine { line ->
                val segment = parseSidecarLine(dir, line) ?: return@forEachLine
                if (queue.item(UploadItem.keyOf(segment.sessionId, segment.tier, segment.seq)) == null) {
                    uploader.enqueue(segment)
                    recovered += 1
                }
            }
        }
        if (recovered > 0) {
            logger.info(TAG, "Recovered $recovered segment(s) from sidecars.")
        }
    }

    private fun parseSidecarLine(sessionDir: File, line: String): SegmentRecord? =
        try {
            val json = JSONObject(line)
            SegmentRecord(
                sessionId = json.getString("sessionId"),
                slot = json.getString("slot"),
                tier = json.getString("tier"),
                seq = json.getLong("seq"),
                file = File(sessionDir, json.getString("file")),
                bytes = json.getLong("bytes"),
                sha256 = json.getString("sha256"),
                mediaStartServerMs = json.getLong("mediaStartServerMs"),
                durationMs = json.getLong("durationMs"),
                frames = json.optInt("frames"),
                offsetMs = json.optLong("offsetMs"),
                rttMs = json.optLong("rttMs"),
            )
        } catch (error: Exception) {
            null
        }

    /** Stores the upload grant before the first segment can be enqueued (both on the upload thread). */
    private fun rememberGrant(command: RecordStart, restart: Boolean) {
        uploadExecutor.execute {
            val fresh = UploadSession.from(command, slot(), System.currentTimeMillis())
            val existing = queue.session(command.sessionId)
            val merged = existing?.copy(
                uploadGrant = fresh.uploadGrant,
                ingestUrl = fresh.ingestUrl,
                grantExpMs = fresh.grantExpMs,
                tiersCsv = fresh.tiersCsv,
                stoppedAtMs = if (restart) 0 else existing.stoppedAtMs,
                manifestState = if (restart) null else existing.manifestState,
            ) ?: fresh
            queue.upsertSession(merged)
        }
    }

    @Synchronized
    private fun scheduleMaxDuration(command: RecordStart) {
        maxDurationStop?.cancel(false)
        maxDurationStop = null
        if (command.maxDurationS <= 0) {
            return
        }
        val stopAtDeviceMs = clockEstimator.toDeviceMs(command.startAtServerMs + command.maxDurationS * 1_000L)
        val delayMs = (stopAtDeviceMs - System.currentTimeMillis()).coerceAtLeast(0)
        maxDurationStop = scheduler.schedule(
            { stateMachine.onLocalStop(command.sessionId, CourtStateMachine.REASON_MAX_DURATION) },
            delayMs,
            TimeUnit.MILLISECONDS,
        )
    }

    @Synchronized
    private fun cancelMaxDuration() {
        maxDurationStop?.cancel(false)
        maxDurationStop = null
    }

    /** Adds grant bookkeeping and the max-duration timer around the camera recorder. */
    private inner class RecorderPort : CourtRecorderPort {
        override fun prepare(sessionId: String, profile: RecordProfile) = recorder.prepare(sessionId, profile)

        override fun start(command: RecordStart, profile: RecordProfile) {
            rememberGrant(command, restart = true)
            scheduleMaxDuration(command)
            recorder.start(command, profile)
        }

        override fun refresh(command: RecordStart) {
            rememberGrant(command, restart = false)
            scheduleMaxDuration(command)
            recorder.refresh(command)
        }

        override fun stop(sessionId: String, stopAtServerMs: Long, reason: String) {
            cancelMaxDuration()
            recorder.stop(sessionId, stopAtServerMs, reason)
        }

        override fun disarm(sessionId: String) = recorder.disarm(sessionId)
    }

    private inner class RecorderEvents : CourtRecorderListener {
        override fun onRecordingStarted(sessionId: String, firstFrameServerMs: Long, profile: RecordProfile) {
            ws.sendEvent(
                C1.RECORDING_STARTED,
                C1Events.recordingStarted(sessionId, firstFrameServerMs, clockEstimator.offsetMs(), profile),
            )
            ws.sendStateNow()
        }

        override fun onSegment(segment: SegmentRecord) {
            ws.sendEvent(C1.RECORDING_SEGMENT, C1Events.recordingSegment(segment))
            uploadExecutor.execute {
                uploader.enqueue(segment)
                refreshPendingCounts()
            }
            kickUploads()
        }

        override fun onRecordingStopped(sessionId: String, lastSeqProxy: Long, lastSeqMaster: Long, reason: String) {
            ws.sendEvent(
                C1.RECORDING_STOPPED,
                C1Events.recordingStopped(sessionId, lastSeqProxy, lastSeqMaster, reason),
            )
            cancelMaxDuration()
            stateMachine.onRecorderStopped(sessionId)
            uploadExecutor.execute { uploader.onSessionStopped(sessionId, lastSeqProxy, lastSeqMaster) }
            kickUploads()
            ws.sendStateNow()
        }

        override fun onRecorderFailed(sessionId: String, error: String) {
            stateMachine.onRecorderFailed(sessionId, error)
            ws.sendStateNow()
        }
    }

    companion object {
        private const val TAG = "CourtRuntime"
        private const val ROOT_RECHECK_MS = 60_000L
        private const val UPLOAD_BATCH = 50
        private const val UPLOAD_MIN_DELAY_MS = 250L
        private const val UPLOAD_IDLE_MS = 30_000L

        @Volatile
        private var instance: CourtRuntime? = null

        fun get(context: Context): CourtRuntime =
            instance ?: synchronized(this) {
                instance ?: CourtRuntime(context).also { instance = it }
            }
    }
}
