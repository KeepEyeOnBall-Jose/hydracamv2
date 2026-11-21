package com.amaia23.hydracam.phonecore

import org.json.JSONObject
import java.io.IOException
import kotlin.math.abs

/** Outcome of inspecting a `hello` ack's `contractVersion` against [C1.CONTRACT_VERSION]. */
sealed class HelloAckOutcome {
    data object Ignored : HelloAckOutcome()

    data object MissingVersion : HelloAckOutcome()

    data class Matched(val version: String) : HelloAckOutcome()

    data class Skewed(val version: String, val skew: ContractSkew) : HelloAckOutcome()

    data class InvalidVersion(val raw: Any) : HelloAckOutcome()
}

/** Decision for an incoming server command relative to the current clock estimate. */
sealed class CommandResyncDecision {
    data object DispatchNow : CommandResyncDecision()

    data object HeldDuringResync : CommandResyncDecision()

    data class StartResync(val driftMs: Long) : CommandResyncDecision()
}

/**
 * Pure protocol helpers for the C1 WebSocket client: pong sample parsing, contract version
 * negotiation, auth/HTTP failure labels, and token invalidation rules.
 */
object CourtWsProtocol {
    fun authFailureReason(error: IOException): String = when (error) {
        is CourtAuthException -> if (error.rejected) "auth_rejected" else "auth_unavailable"
        else -> "auth_unreachable"
    }

    fun httpFailureReason(statusCode: Int): String = "http_$statusCode"

    fun closeReason(code: Int): String = "closed_$code"

    fun shouldInvalidateToken(statusCode: Int?): Boolean = statusCode == HttpStatus.UNAUTHORIZED

    /** A pong missing a time, or with times out of order, would win the min-RTT pick, so it is dropped. */
    fun parseClockPong(body: JSONObject, receivedAtMs: Long): ClockSample? {
        val sample = try {
            ClockSample(
                t0 = body.optLongOrNull("t0") ?: -1,
                t1 = body.optLongOrNull("t1") ?: -1,
                t2 = body.optLongOrNull("t2") ?: -1,
                t3 = receivedAtMs,
            )
        } catch (ignored: C1ProtocolException) {
            return null
        }
        return sample.takeIf { it.t0 in 0..receivedAtMs && it.t1 >= 0 && it.t2 >= it.t1 }
    }

    fun parseHelloAckVersion(body: JSONObject): HelloAckOutcome {
        val raw = body.opt("contractVersion")
        return when {
            raw == null || raw == JSONObject.NULL -> HelloAckOutcome.MissingVersion
            raw !is String -> HelloAckOutcome.InvalidVersion(raw)
            else -> when (val skew = C1.contractSkew(raw)) {
                ContractSkew.SAME -> HelloAckOutcome.Matched(raw)
                ContractSkew.OLDER, ContractSkew.NEWER -> HelloAckOutcome.Skewed(raw, skew)
                ContractSkew.UNKNOWN -> HelloAckOutcome.InvalidVersion(raw)
            }
        }
    }
}

/**
 * Ordered hold queue for server commands received while a clock resync burst is in flight.
 * Caller-synchronized alongside the client's hold timeout state.
 */
class CommandResyncHold {
    private val heldCommands = ArrayDeque<C1Envelope>()

    var isHolding: Boolean = false
        private set

    fun accept(envelope: C1Envelope, serverNowMs: Long, maxDriftMs: Long): CommandResyncDecision {
        if (isHolding) {
            heldCommands += envelope
            return CommandResyncDecision.HeldDuringResync
        }
        val driftMs = if (envelope.ts > 0) envelope.ts - serverNowMs else 0L
        if (abs(driftMs) <= maxDriftMs) {
            return CommandResyncDecision.DispatchNow
        }
        isHolding = true
        heldCommands += envelope
        return CommandResyncDecision.StartResync(driftMs)
    }

    /** Pops the next held command in arrival order, or clears [isHolding] when the queue empties. */
    fun pollNextOrFinish(): C1Envelope? = heldCommands.removeFirstOrNull().also {
        if (it == null) {
            isHolding = false
        }
    }

    fun clear() {
        heldCommands.clear()
        isHolding = false
    }
}

/**
 * Generation-fenced WebSocket connection and reconnect-backoff state tracker.
 * Caller-synchronized alongside socket/executor handles.
 */
class WsConnectionState(private val backoff: ReconnectBackoff = ReconnectBackoff()) {
    var running: Boolean = false
        private set

    var generation: Int = 0
        private set

    var open: Boolean = false
        private set

    var serverContractVersion: String? = null
        private set

    var lastConnectError: String? = null
        private set

    var connectedAtMs: Long = 0
        private set

    var pendingHelloId: String? = null
        private set

    /** Starts the session; returns the generation to connect under, or null if already running. */
    fun beginStart(): Int? {
        if (running) {
            return null
        }
        running = true
        return generation
    }

    /** Stops the session and invalidates all in-flight generations. Returns whether it was open. */
    fun stop(): Boolean {
        val wasOpen = open
        running = false
        generation += 1
        pendingHelloId = null
        serverContractVersion = null
        open = false
        return wasOpen
    }

    fun isCurrentConnect(expectedGeneration: Int): Boolean = running && generation == expectedGeneration

    fun onOpened(listenerGeneration: Int, nowMs: Long): Boolean {
        if (listenerGeneration != generation) {
            return false
        }
        open = true
        connectedAtMs = nowMs
        lastConnectError = null
        backoff.reset()
        return true
    }

    fun onHelloPrepared(helloId: String) {
        pendingHelloId = helloId
        serverContractVersion = null
    }

    fun evaluateHelloAck(body: JSONObject): HelloAckOutcome {
        val ref = body.optString("ref")
        if (pendingHelloId == null || ref != pendingHelloId) {
            return HelloAckOutcome.Ignored
        }
        pendingHelloId = null
        val outcome = CourtWsProtocol.parseHelloAckVersion(body)
        serverContractVersion = when (outcome) {
            is HelloAckOutcome.Matched -> outcome.version
            is HelloAckOutcome.Skewed -> outcome.version
            HelloAckOutcome.MissingVersion, is HelloAckOutcome.InvalidVersion, HelloAckOutcome.Ignored -> null
        }
        return outcome
    }

    /** Marks the active generation dropped; returns the new generation or null if [listenerGeneration] is stale. */
    fun onDropped(listenerGeneration: Int): Int? {
        if (listenerGeneration != generation) {
            return null
        }
        generation += 1
        open = false
        pendingHelloId = null
        serverContractVersion = null
        return generation
    }

    /** Records [reason] and returns the reconnect delay if [failedGeneration] should still retry. */
    fun scheduleRetryDelayMs(failedGeneration: Int, reason: String): Long? {
        val delayMs = backoff.nextDelayMs()
        lastConnectError = reason
        return if (running && failedGeneration == generation) delayMs else null
    }
}
