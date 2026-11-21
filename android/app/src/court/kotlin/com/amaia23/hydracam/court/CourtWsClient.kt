package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.CommandResyncDecision
import com.amaia23.hydracam.phonecore.CommandResyncHold
import com.amaia23.hydracam.phonecore.CourtWsProtocol
import com.amaia23.hydracam.phonecore.HelloAckOutcome
import com.amaia23.hydracam.phonecore.WsConnectionState
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

typealias EventOutbox = com.amaia23.hydracam.phonecore.EventOutbox

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
    backoff: ReconnectBackoff = ReconnectBackoff(),
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
    private val wsState = WsConnectionState(backoff)
    private val resyncHold = CommandResyncHold()
    private var socket: WebSocket? = null
    private var reconnectTask: ScheduledFuture<*>? = null
    private val periodicTasks = mutableListOf<ScheduledFuture<*>>()
    private var holdTimeout: ScheduledFuture<*>? = null

    val serverContractVersion: String?
        @Synchronized get() = wsState.serverContractVersion

    val lastConnectError: String?
        @Synchronized get() = wsState.lastConnectError

    val connectedAtMs: Long
        @Synchronized get() = wsState.connectedAtMs

    val isOpen: Boolean
        @Synchronized get() = wsState.open

    fun start() {
        val startedGeneration = synchronized(this) { wsState.beginStart() } ?: return
        scheduler.execute { connect(startedGeneration) }
    }

    fun stop() {
        synchronized(this) {
            wsState.stop()
            reconnectTask?.cancel(false)
            cancelPeriodic()
            holdTimeout?.cancel(false)
            holdTimeout = null
            resyncHold.clear()
            socket?.close(NORMAL_CLOSURE, "stopping")
            socket = null
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
        if (synchronized(this) { !wsState.isCurrentConnect(currentGeneration) }) return
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
            if (wsState.isCurrentConnect(currentGeneration)) {
                socket = http.newWebSocket(request, listener)
            }
        }
    }

    /** The access token, or null after scheduling a reconnect that says why there is none. */
    private fun accessTokenOrRetry(currentGeneration: Int): String? {
        val failure = try {
            return tokens.accessToken()
        } catch (error: IOException) {
            CourtWsProtocol.authFailureReason(error)
        }
        failAndRetry(currentGeneration, failure)
        return null
    }

    private inner class Listener(private val listenerGeneration: Int) : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            val accepted = synchronized(this@CourtWsClient) {
                wsState.onOpened(listenerGeneration, clock.nowMs())
            }
            if (!accepted) {
                webSocket.close(NORMAL_CLOSURE, "stale")
                return
            }
            logger.info(TAG, "Connected to K2.")
            onConnectionChanged(true, null)
            scheduler.execute { onOpened() }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (listenerGeneration != synchronized(this@CourtWsClient) { wsState.generation }) {
                return
            }
            handleMessage(text)
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(NORMAL_CLOSURE, null)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            dropped(listenerGeneration, CourtWsProtocol.closeReason(code))
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (CourtWsProtocol.shouldInvalidateToken(response?.code)) {
                tokens.invalidate()
            }
            val reason = response?.let { CourtWsProtocol.httpFailureReason(it.code) } ?: t.javaClass.simpleName
            dropped(listenerGeneration, reason)
        }
    }

    private fun onOpened() {
        val helloEnvelope = C1Envelope.create(C1.HELLO, hello().toJson(), serverNow())
        synchronized(this) { wsState.onHelloPrepared(helloEnvelope.id) }
        sendRaw(helloEnvelope)
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
            C1.ACK -> onAck(envelope.body)
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

    private fun onAck(body: JSONObject) {
        val ref = body.optString("ref")
        outbox.ack(ref)
        when (val outcome = synchronized(this) { wsState.evaluateHelloAck(body) }) {
            HelloAckOutcome.Ignored -> Unit
            HelloAckOutcome.MissingVersion ->
                logger.info(TAG, "K2 acked hello without contractVersion (server < 1.29).")
            is HelloAckOutcome.Matched ->
                logger.info(TAG, "K2 contract ${outcome.version} matches K1 ${C1.CONTRACT_VERSION}.")
            is HelloAckOutcome.Skewed ->
                logger.warn(TAG, "K2 contract skew: server=${outcome.version}, device=${C1.CONTRACT_VERSION}.")
            is HelloAckOutcome.InvalidVersion ->
                logger.warn(TAG, "K2 acked hello with invalid contractVersion '${outcome.raw}'.")
        }
    }

    private fun onServerCommand(envelope: C1Envelope) {
        val decision = synchronized(this) {
            val result = resyncHold.accept(envelope, serverNow(), clockResyncDriftMs)
            if (result is CommandResyncDecision.StartResync) {
                clockEstimator.markStale()
                holdTimeout = scheduler.schedule(
                    { releaseHeld(timedOut = true) },
                    clockResyncHoldMs,
                    TimeUnit.MILLISECONDS,
                )
            }
            result
        }
        when (decision) {
            CommandResyncDecision.DispatchNow -> onCommand(envelope)
            CommandResyncDecision.HeldDuringResync -> Unit
            is CommandResyncDecision.StartResync -> {
                logger.warn(
                    TAG,
                    "${envelope.type} server time is ${decision.driftMs} ms off our clock; re-syncing first.",
                )
                startClockBurst()
            }
        }
    }

    /** Hands held commands on in order; only the first caller (pong or hold timeout) drains. */
    private fun releaseHeld(timedOut: Boolean) {
        val claimed = synchronized(this) { holdTimeout?.also { holdTimeout = null } } ?: return
        claimed.cancel(false)
        if (timedOut) {
            logger.warn(TAG, "No clock.pong within $clockResyncHoldMs ms; handling held commands on the old offset.")
        }
        while (true) {
            val next = synchronized(this) { resyncHold.pollNextOrFinish() } ?: return
            onCommand(next)
        }
    }

    private fun onClockPong(body: JSONObject) {
        val sample = CourtWsProtocol.parseClockPong(body, clock.nowMs())
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
        val target = synchronized(this) { if (wsState.open) socket else null } ?: return false
        return target.send(envelope.encode())
    }

    private fun dropped(listenerGeneration: Int, reason: String) {
        val nextGeneration = synchronized(this) {
            wsState.onDropped(listenerGeneration)?.also {
                socket = null
                cancelPeriodic()
            }
        } ?: return
        logger.info(TAG, "Disconnected from K2: $reason")
        onConnectionChanged(false, reason)
        failAndRetry(nextGeneration, reason)
    }

    private fun failAndRetry(failedGeneration: Int, reason: String) {
        val delayMs = synchronized(this) {
            val delay = wsState.scheduleRetryDelayMs(failedGeneration, reason) ?: return
            reconnectTask?.cancel(false)
            reconnectTask = scheduler.schedule({ connect(failedGeneration) }, delay, TimeUnit.MILLISECONDS)
            delay
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
