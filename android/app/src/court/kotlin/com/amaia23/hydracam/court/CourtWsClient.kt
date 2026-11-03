package com.amaia23.hydracam.court

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Durable store of device events K2 has not acked yet. C1: un-acked events are re-sent with the
 * same id, so they must survive reconnects and process death.
 */
class EventOutbox(
    private val directory: File?,
    private val maxEntries: Int = 5_000,
    private val logger: CourtLogger = NoopCourtLogger,
) {
    private data class Entry(val envelope: C1Envelope, val order: Long, var lastSentAtMs: Long)

    private val entries = LinkedHashMap<String, Entry>()
    private var nextOrder = 0L

    init {
        load()
    }

    @Synchronized
    fun add(envelope: C1Envelope) {
        val entry = Entry(envelope, nextOrder++, lastSentAtMs = 0)
        entries[envelope.id] = entry
        persist(entry)
        while (entries.size > maxEntries) {
            val oldest = entries.values.first()
            logger.warn(TAG, "Outbox full; dropping ${oldest.envelope.type} id=${oldest.envelope.id}.")
            remove(oldest.envelope.id)
        }
    }

    /** Returns true when [id] was pending. */
    @Synchronized
    fun ack(id: String): Boolean = remove(id)

    @Synchronized
    fun size(): Int = entries.size

    @Synchronized
    fun pendingIds(): List<String> = entries.keys.toList()

    /** Entries never sent, or sent longer than [resendAfterMs] ago. Marks them sent at [nowMs]. */
    @Synchronized
    fun takeDue(nowMs: Long, resendAfterMs: Long): List<C1Envelope> {
        val due = entries.values.filter {
            it.lastSentAtMs == 0L || nowMs - it.lastSentAtMs >= resendAfterMs
        }
        due.forEach { it.lastSentAtMs = nowMs }
        return due.map { it.envelope }
    }

    /** New connection: everything pending is due again. */
    @Synchronized
    fun markAllUnsent() {
        entries.values.forEach { it.lastSentAtMs = 0 }
    }

    private fun remove(id: String): Boolean {
        val entry = entries.remove(id) ?: return false
        directory?.let { File(it, fileName(entry)).delete() }
        return true
    }

    private fun persist(entry: Entry) {
        val dir = directory ?: return
        val json = JSONObject()
            .put("order", entry.order)
            .put("envelope", JSONObject(entry.envelope.encode()))
        try {
            dir.mkdirs()
            val temp = File(dir, fileName(entry) + ".tmp")
            // Synced before the rename, so a power cut cannot leave an empty file that load() drops.
            FileOutputStream(temp).use { stream ->
                stream.write(json.toString().toByteArray())
                stream.fd.sync()
            }
            if (!temp.renameTo(File(dir, fileName(entry)))) {
                throw IOException("rename failed")
            }
        } catch (error: IOException) {
            logger.warn(TAG, "Could not persist outbox entry ${entry.envelope.id}.", error)
        }
    }

    private fun load() {
        val dir = directory ?: return
        val files = dir.listFiles { file -> file.name.endsWith(".json") } ?: return
        val loaded = files.mapNotNull { file ->
            val failure: Exception = try {
                val json = JSONObject(file.readText())
                val envelope = C1Envelope.decode(json.getJSONObject("envelope").toString())
                return@mapNotNull Entry(envelope, json.getLong("order"), lastSentAtMs = 0)
            } catch (error: IOException) {
                error
            } catch (error: JSONException) {
                error
            } catch (error: C1ProtocolException) {
                error
            }
            logger.warn(TAG, "Dropping unreadable outbox file ${file.name}.", failure)
            file.delete()
            null
        }
        loaded.sortedBy { it.order }.forEach { entries[it.envelope.id] = it }
        nextOrder = (loaded.maxOfOrNull { it.order } ?: -1) + 1
    }

    private fun fileName(entry: Entry): String = "%012d-%s.json".format(entry.order, entry.envelope.id)

    private companion object {
        const val TAG = "CourtOutbox"
    }
}

/**
 * H4: C1 v1 WebSocket client.
 *
 * - On open: `hello`, then every un-acked event again (same ids), then `state` every [stateIntervalMs].
 * - A `clock.ping` burst runs on connect and every [clockIntervalMs] (H10). A command whose `ts` is more
 *   than [clockResyncDriftMs] off our estimate of server time starts a burst too, and commands are held
 *   (in order) until its first pong, at most [clockResyncHoldMs], so nothing schedules on a stale offset.
 * - Cloud commands go to [onCommand], which must answer through [reply] within 5 s.
 * - Reconnects with [ReconnectBackoff] (jittered, ≤ 30 s). A 401 drops the cached token.
 */
// Each parameter is a port or a C1 timing the runtime wires; this constructor is the only DI seam.
@Suppress("LongParameterList")
class CourtWsClient(
    private val http: OkHttpClient,
    private val webSocketUrl: () -> String?,
    private val tokens: AccessTokenProvider,
    private val hello: () -> HelloBody,
    private val state: () -> StateBody,
    private val outbox: EventOutbox,
    private val clockEstimator: ClockOffsetEstimator,
    private val onCommand: (C1Envelope) -> Unit,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val backoff: ReconnectBackoff = ReconnectBackoff(),
    private val logger: CourtLogger = NoopCourtLogger,
    private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor(),
    private val stateIntervalMs: Long = 5_000,
    private val resendAfterMs: Long = 10_000,
    private val resendCheckMs: Long = 2_000,
    private val clockBurstSize: Int = 8,
    private val clockPingSpacingMs: Long = 250,
    private val clockIntervalMs: Long = 300_000,
    private val clockResyncDriftMs: Long = 1_000,
    private val clockResyncHoldMs: Long = 2_000,
    private val onConnectionChanged: (Boolean, String?) -> Unit = { _, _ -> },
) {
    private var socket: WebSocket? = null
    private var generation = 0
    private var open = false
    private var running = false
    private var reconnectTask: ScheduledFuture<*>? = null
    private val periodicTasks = mutableListOf<ScheduledFuture<*>>()
    private val heldCommands = ArrayDeque<C1Envelope>()
    private var holding = false
    private var holdTimeout: ScheduledFuture<*>? = null

    @get:Synchronized
    var lastConnectError: String? = null
        private set

    @get:Synchronized
    var connectedAtMs: Long = 0
        private set

    val isOpen: Boolean
        @Synchronized get() = open

    fun start() {
        val startedGeneration = synchronized(this) {
            if (running) {
                return
            }
            running = true
            generation
        }
        scheduler.execute { connect(startedGeneration) }
    }

    fun stop() {
        synchronized(this) {
            running = false
            generation += 1
            reconnectTask?.cancel(false)
            cancelPeriodic()
            holdTimeout?.cancel(false)
            holdTimeout = null
            heldCommands.clear()
            holding = false
            socket?.close(NORMAL_CLOSURE, "stopping")
            socket = null
            open = false
        }
        onConnectionChanged(false, "stopped")
    }

    /** Durable device event (`recording.*`): kept until K2 acks it. Returns the envelope id. */
    fun sendEvent(type: String, body: JSONObject): String {
        val envelope = C1Envelope.create(type, body, serverNow())
        outbox.add(envelope)
        scheduler.execute { flushOutbox() }
        return envelope.id
    }

    /** Best-effort send: ack/nack replies, `state`, `clock.ping`. */
    fun reply(envelope: C1Envelope) {
        sendRaw(envelope)
    }

    fun sendStateNow() {
        scheduler.execute { sendState() }
    }

    /** Opens a socket for [currentGeneration]; a connect queued before a stop/start opens nothing. */
    private fun connect(currentGeneration: Int) {
        if (synchronized(this) { !running || generation != currentGeneration }) return
        val url = webSocketUrl()
        if (url == null) {
            failAndRetry(currentGeneration, "not_enrolled")
            return
        }
        val token = accessTokenOrRetry(currentGeneration) ?: return
        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .build()
        val listener = Listener(currentGeneration)
        synchronized(this) {
            if (running && generation == currentGeneration) {
                socket = http.newWebSocket(request, listener)
            }
        }
    }

    /** The access token, or null after scheduling a reconnect that says why there is none. */
    private fun accessTokenOrRetry(currentGeneration: Int): String? {
        val failure = try {
            return tokens.accessToken()
        } catch (error: CourtAuthException) {
            if (error.rejected) "auth_rejected" else "auth_unavailable"
        } catch (ignored: IOException) {
            "auth_unreachable"
        }
        failAndRetry(currentGeneration, failure)
        return null
    }

    private inner class Listener(private val listenerGeneration: Int) : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            synchronized(this@CourtWsClient) {
                if (listenerGeneration != generation) {
                    webSocket.close(NORMAL_CLOSURE, "stale")
                    return
                }
                open = true
                connectedAtMs = clock.nowMs()
                lastConnectError = null
            }
            backoff.reset()
            logger.info(TAG, "Connected to K2.")
            onConnectionChanged(true, null)
            scheduler.execute { onOpened() }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (listenerGeneration != synchronized(this@CourtWsClient) { generation }) {
                return
            }
            handleMessage(text)
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(NORMAL_CLOSURE, null)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            dropped(listenerGeneration, "closed_$code")
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (response?.code == HttpStatus.UNAUTHORIZED) {
                tokens.invalidate()
            }
            val reason = response?.let { "http_${it.code}" } ?: (t.javaClass.simpleName)
            dropped(listenerGeneration, reason)
        }
    }

    private fun onOpened() {
        sendRaw(C1Envelope.create(C1.HELLO, hello().toJson(), serverNow()))
        outbox.markAllUnsent()
        flushOutbox()
        sendState()
        startClockBurst()
        synchronized(this) {
            cancelPeriodic()
            periodicTasks += scheduler.scheduleWithFixedDelay(
                { sendState() },
                stateIntervalMs,
                stateIntervalMs,
                TimeUnit.MILLISECONDS,
            )
            periodicTasks += scheduler.scheduleWithFixedDelay(
                { flushOutbox() },
                resendCheckMs,
                resendCheckMs,
                TimeUnit.MILLISECONDS,
            )
            periodicTasks += scheduler.scheduleWithFixedDelay(
                { startClockBurst() },
                clockIntervalMs,
                clockIntervalMs,
                TimeUnit.MILLISECONDS,
            )
        }
    }

    private fun handleMessage(text: String) {
        val envelope = try {
            C1Envelope.decode(text)
        } catch (error: C1ProtocolException) {
            logger.warn(TAG, "Dropping bad envelope: ${error.message}")
            return
        }
        when (envelope.type) {
            C1.ACK -> outbox.ack(envelope.body.optString("ref"))
            C1.NACK -> {
                val ref = envelope.body.optString("ref")
                if (outbox.ack(ref)) {
                    logger.warn(TAG, "K2 nacked event $ref: ${envelope.body.optString("code")}")
                }
            }
            C1.CLOCK_PONG -> onClockPong(envelope.body)
            else -> onServerCommand(envelope)
        }
    }

    private fun onServerCommand(envelope: C1Envelope) {
        val driftMs = if (envelope.ts > 0) envelope.ts - serverNow() else 0L
        val resync: Boolean
        synchronized(this) {
            if (holding) {
                heldCommands += envelope
                return
            }
            resync = abs(driftMs) > clockResyncDriftMs
            if (resync) {
                holding = true
                heldCommands += envelope
                clockEstimator.markStale()
                holdTimeout = scheduler.schedule(
                    { releaseHeld(timedOut = true) },
                    clockResyncHoldMs,
                    TimeUnit.MILLISECONDS,
                )
            }
        }
        if (!resync) {
            onCommand(envelope)
            return
        }
        logger.warn(TAG, "${envelope.type} server time is $driftMs ms off our clock; re-syncing first.")
        startClockBurst()
    }

    /** Hands held commands on in order; only the first caller (pong or hold timeout) drains. */
    private fun releaseHeld(timedOut: Boolean) {
        val claimed = synchronized(this) { holdTimeout?.also { holdTimeout = null } } ?: return
        claimed.cancel(false)
        if (timedOut) {
            logger.warn(TAG, "No clock.pong within $clockResyncHoldMs ms; handling held commands on the old offset.")
        }
        while (true) {
            val next = synchronized(this) {
                heldCommands.removeFirstOrNull().also { if (it == null) holding = false }
            } ?: return
            onCommand(next)
        }
    }

    /** A pong missing a time, or with times out of order, would win the min-RTT pick, so it is dropped. */
    private fun onClockPong(body: JSONObject) {
        val t3 = clock.nowMs()
        val sample = try {
            ClockSample(
                t0 = body.optLongOrNull("t0") ?: -1,
                t1 = body.optLongOrNull("t1") ?: -1,
                t2 = body.optLongOrNull("t2") ?: -1,
                t3 = t3,
            ).takeIf { it.t0 in 0..t3 && it.t1 >= 0 && it.t2 >= it.t1 }
        } catch (ignored: C1ProtocolException) {
            null
        }
        if (sample == null) {
            logger.warn(TAG, "Dropping malformed clock.pong.")
            return
        }
        if (clockEstimator.add(sample)) {
            logger.info(TAG, "Clock burst done: ${clockEstimator.current()}.")
        }
        if (!clockEstimator.isStale()) {
            releaseHeld(timedOut = false)
        }
    }

    private fun startClockBurst() {
        clockEstimator.beginBurst()
        for (index in 0 until clockBurstSize) {
            scheduler.schedule(
                {
                    val t0 = clock.nowMs()
                    sendRaw(C1Envelope.create(C1.CLOCK_PING, JSONObject().put("t0", t0), t0))
                },
                index * clockPingSpacingMs,
                TimeUnit.MILLISECONDS,
            )
        }
    }

    private fun sendState() {
        if (!isOpen) {
            return
        }
        sendRaw(C1Envelope.create(C1.STATE, state().toJson(), serverNow()))
    }

    private fun flushOutbox() {
        if (!isOpen) {
            return
        }
        outbox.takeDue(clock.nowMs(), resendAfterMs).forEach { sendRaw(it) }
    }

    private fun sendRaw(envelope: C1Envelope): Boolean {
        val target = synchronized(this) { if (open) socket else null } ?: return false
        return target.send(envelope.encode())
    }

    private fun dropped(listenerGeneration: Int, reason: String) {
        synchronized(this) {
            if (listenerGeneration != generation) {
                return
            }
            generation += 1
            open = false
            socket = null
            cancelPeriodic()
        }
        logger.info(TAG, "Disconnected from K2: $reason")
        onConnectionChanged(false, reason)
        failAndRetry(synchronized(this) { generation }, reason)
    }

    private fun failAndRetry(failedGeneration: Int, reason: String) {
        val delayMs = backoff.nextDelayMs()
        synchronized(this) {
            lastConnectError = reason
            if (!running || failedGeneration != generation) {
                return
            }
            reconnectTask?.cancel(false)
            reconnectTask = scheduler.schedule({ connect(failedGeneration) }, delayMs, TimeUnit.MILLISECONDS)
        }
        logger.info(TAG, "Reconnect in $delayMs ms ($reason).")
    }

    private fun cancelPeriodic() {
        periodicTasks.forEach { it.cancel(false) }
        periodicTasks.clear()
    }

    private fun serverNow(): Long = clockEstimator.toServerMs(clock.nowMs())

    private companion object {
        const val TAG = "CourtWs"
        const val NORMAL_CLOSURE = 1000
    }
}
