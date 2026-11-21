package com.amaia23.hydracam.phonecore

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import kotlin.random.Random

class CourtWsCoreTest {
    @Test
    fun protocolFailureReasonsAndTokenInvalidationMapCorrectly() {
        assertEquals("auth_rejected", CourtWsProtocol.authFailureReason(CourtAuthException("bad", rejected = true)))
        assertEquals(
            "auth_unavailable",
            CourtWsProtocol.authFailureReason(CourtAuthException("later", rejected = false)),
        )
        assertEquals("auth_unreachable", CourtWsProtocol.authFailureReason(IOException("dns")))
        assertEquals("http_500", CourtWsProtocol.httpFailureReason(500))
        assertEquals("closed_1000", CourtWsProtocol.closeReason(1000))
        assertTrue(CourtWsProtocol.shouldInvalidateToken(HttpStatus.UNAUTHORIZED))
        assertFalse(CourtWsProtocol.shouldInvalidateToken(HttpStatus.FORBIDDEN))
        assertFalse(CourtWsProtocol.shouldInvalidateToken(null))
    }

    @Test
    fun parseClockPongAcceptsValidSamplesAndDropsMalformedOnes() {
        val valid = JSONObject().put("t0", 100L).put("t1", 1_100L).put("t2", 1_105L)
        assertEquals(ClockSample(100L, 1_100L, 1_105L, 120L), CourtWsProtocol.parseClockPong(valid, 120L))

        val missing = JSONObject().put("t0", 100L)
        assertNull(CourtWsProtocol.parseClockPong(missing, 120L))

        val negativeT0 = JSONObject().put("t0", -1L).put("t1", 10L).put("t2", 10L)
        assertNull(CourtWsProtocol.parseClockPong(negativeT0, 120L))

        val futureT0 = JSONObject().put("t0", 121L).put("t1", 10L).put("t2", 10L)
        assertNull(CourtWsProtocol.parseClockPong(futureT0, 120L))

        val negativeT1 = JSONObject().put("t0", 100L).put("t1", -1L).put("t2", 10L)
        assertNull(CourtWsProtocol.parseClockPong(negativeT1, 120L))

        val swapped = JSONObject().put("t0", 100L).put("t1", 200L).put("t2", 199L)
        assertNull(CourtWsProtocol.parseClockPong(swapped, 120L))

        val nonInteger = JSONObject().put("t0", 100.5).put("t1", 1_100L).put("t2", 1_100L)
        assertNull(CourtWsProtocol.parseClockPong(nonInteger, 120L))
    }

    @Test
    fun helloAckNegotiatesContractVersionAndIgnoresNonHelloRefs() {
        val state = WsConnectionState()
        state.onHelloPrepared("hello-1")

        assertEquals(
            HelloAckOutcome.Ignored,
            state.evaluateHelloAck(JSONObject().put("ref", "other").put("contractVersion", "1.29")),
        )
        assertEquals("hello-1", state.pendingHelloId)

        assertEquals(
            HelloAckOutcome.Matched(C1.CONTRACT_VERSION),
            state.evaluateHelloAck(JSONObject().put("ref", "hello-1").put("contractVersion", C1.CONTRACT_VERSION)),
        )
        assertNull(state.pendingHelloId)
        assertEquals(C1.CONTRACT_VERSION, state.serverContractVersion)

        // Ignored after pendingHelloId cleared.
        assertEquals(
            HelloAckOutcome.Ignored,
            state.evaluateHelloAck(JSONObject().put("ref", "hello-1").put("contractVersion", "9.9")),
        )
        assertEquals(C1.CONTRACT_VERSION, state.serverContractVersion)

        state.onHelloPrepared("hello-2")
        assertEquals(HelloAckOutcome.MissingVersion, state.evaluateHelloAck(JSONObject().put("ref", "hello-2")))
        assertNull(state.serverContractVersion)

        state.onHelloPrepared("hello-3")
        assertEquals(
            HelloAckOutcome.MissingVersion,
            state.evaluateHelloAck(JSONObject().put("ref", "hello-3").put("contractVersion", JSONObject.NULL)),
        )

        state.onHelloPrepared("hello-4")
        assertEquals(
            HelloAckOutcome.Skewed("1.28", ContractSkew.OLDER),
            state.evaluateHelloAck(JSONObject().put("ref", "hello-4").put("contractVersion", "1.28")),
        )
        assertEquals("1.28", state.serverContractVersion)

        state.onHelloPrepared("hello-5")
        assertEquals(
            HelloAckOutcome.InvalidVersion("bad"),
            state.evaluateHelloAck(JSONObject().put("ref", "hello-5").put("contractVersion", "bad")),
        )
        assertNull(state.serverContractVersion)

        state.onHelloPrepared("hello-6")
        assertEquals(
            HelloAckOutcome.InvalidVersion(1.29),
            state.evaluateHelloAck(JSONObject().put("ref", "hello-6").put("contractVersion", 1.29)),
        )
        assertNull(state.serverContractVersion)
    }

    @Test
    fun wsConnectionStateTracksGenerationsOpenedDroppedAndBackoff() {
        val state = WsConnectionState(ReconnectBackoff(baseMs = 100, maxMs = 400, random = Random(3)))
        assertEquals(0, state.beginStart())
        assertNull(state.beginStart())
        assertTrue(state.isCurrentConnect(0))
        assertFalse(state.isCurrentConnect(1))

        assertFalse(state.onOpened(listenerGeneration = 1, nowMs = 50L))
        assertFalse(state.open)

        assertTrue(state.onOpened(listenerGeneration = 0, nowMs = 100L))
        assertTrue(state.open)
        assertEquals(100L, state.connectedAtMs)
        assertNull(state.lastConnectError)

        state.onHelloPrepared("h1")
        assertNull(state.onDropped(listenerGeneration = 1))
        assertEquals(1, state.onDropped(listenerGeneration = 0))
        assertFalse(state.open)
        assertNull(state.pendingHelloId)
        assertNull(state.serverContractVersion)

        val delay = state.scheduleRetryDelayMs(failedGeneration = 1, reason = "closed_1000")
        assertTrue(delay != null && delay in 50L..100L)
        assertEquals("closed_1000", state.lastConnectError)

        assertNull(state.scheduleRetryDelayMs(failedGeneration = 0, reason = "stale"))
        assertEquals("stale", state.lastConnectError)

        assertTrue(state.onOpened(listenerGeneration = 1, nowMs = 200L))
        assertTrue(state.stop())
        assertFalse(state.stop())
        assertFalse(state.isCurrentConnect(2))
        assertNull(state.scheduleRetryDelayMs(failedGeneration = 2, reason = "stopped"))
    }

    @Test
    fun commandResyncHoldBuffersDriftedCommandsAndDrainsInOrder() {
        val hold = CommandResyncHold()
        val first = C1Envelope.create(C1.RECORD_START, JSONObject().put("sessionId", "s1"), 1_000L)
        val second = C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), 2_000L)
        val zeroTs = C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), 0L)

        assertEquals(CommandResyncDecision.DispatchNow, hold.accept(zeroTs, serverNowMs = 99_000L, maxDriftMs = 1_000L))
        assertEquals(CommandResyncDecision.DispatchNow, hold.accept(first, serverNowMs = 1_500L, maxDriftMs = 1_000L))
        assertFalse(hold.isHolding)

        assertEquals(
            CommandResyncDecision.StartResync(driftMs = -9_000L),
            hold.accept(first, serverNowMs = 10_000L, maxDriftMs = 1_000L),
        )
        assertTrue(hold.isHolding)
        assertEquals(
            CommandResyncDecision.HeldDuringResync,
            hold.accept(second, serverNowMs = 2_000L, maxDriftMs = 1_000L),
        )

        assertEquals(first, hold.pollNextOrFinish())
        assertTrue(hold.isHolding)
        assertEquals(second, hold.pollNextOrFinish())
        assertNull(hold.pollNextOrFinish())
        assertFalse(hold.isHolding)

        hold.accept(first, serverNowMs = 10_000L, maxDriftMs = 1_000L)
        assertTrue(hold.isHolding)
        hold.clear()
        assertFalse(hold.isHolding)
        assertNull(hold.pollNextOrFinish())
    }
}
