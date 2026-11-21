package com.amaia23.hydracam.phonecore

import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class CourtWsClientTest {
    @get:Rule
    val temp = TemporaryFolder()

    private inner class FakeK2(private val malformedPongs: Boolean = false) : WebSocketListener() {
        @Volatile var skewMs = 1_000L

        @Volatile var answerPings = true
        val pings = AtomicInteger()
        val received = LinkedBlockingQueue<C1Envelope>()
        val opened = LinkedBlockingQueue<WebSocket>()
        val closed = LinkedBlockingQueue<Int>()

        override fun onOpen(webSocket: WebSocket, response: Response) {
            opened.put(webSocket)
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val envelope = C1Envelope.decode(text)
            if (envelope.type == C1.CLOCK_PING && answerPings) {
                pings.incrementAndGet()
                val t0 = envelope.body.getLong("t0")
                if (malformedPongs) {
                    webSocket.send(C1Envelope.create(C1.CLOCK_PONG, JSONObject().put("t0", t0), t0).encode())
                    val swapped = JSONObject().put("t0", t0).put("t1", t0 + 2_000).put("t2", t0 + 1_000)
                    webSocket.send(C1Envelope.create(C1.CLOCK_PONG, swapped, t0).encode())
                }
                val pong = JSONObject().put("t0", t0).put("t1", t0 + skewMs).put("t2", t0 + skewMs)
                webSocket.send(C1Envelope.create(C1.CLOCK_PONG, pong, t0 + skewMs).encode())
            }
            received.put(envelope)
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            closed.put(code)
            webSocket.close(1000, null)
        }

        fun next(type: String): C1Envelope {
            while (true) {
                val envelope = received.awaitReply()
                if (envelope.type == type) {
                    return envelope
                }
            }
        }
    }

    private class FakeTokens : AccessTokenProvider {
        val invalidations = AtomicInteger()

        override fun accessToken(): String = "tok-1"

        override fun invalidate() {
            invalidations.incrementAndGet()
        }
    }

    private class FailingTokens(private val error: IOException) : AccessTokenProvider {
        override fun accessToken(): String = throw error

        override fun invalidate() = Unit
    }

    private val server = MockWebServer()
    private val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
    private val tokens = FakeTokens()
    private val estimator = ClockOffsetEstimator(burstSize = 2)
    private val commands = LinkedBlockingQueue<C1Envelope>()
    private val offsetsAtCommand = LinkedBlockingQueue<Long>()
    private val connections = LinkedBlockingQueue<Boolean>()
    private val reasons = LinkedBlockingQueue<String>()
    private lateinit var scheduler: ScheduledExecutorService
    private lateinit var outbox: EventOutbox
    private lateinit var client: CourtWsClient

    private val caps = CourtCaps("1080p", listOf(30, 60), hevc = false, encoders = 2, torch = true, speaker = true)

    @Before
    fun setUp() {
        server.start()
        scheduler = Executors.newSingleThreadScheduledExecutor()
        outbox = EventOutbox(temp.newFolder("outbox"))
        client = newClient()
    }

    private fun newClient(
        webSocketUrl: () -> String? = { server.url("/device/v1").toString() },
        tokenProvider: AccessTokenProvider = tokens,
        logger: PhoneLogger = NoopPhoneLogger,
    ) = CourtWsClient(
        http = http,
        webSocketUrl = webSocketUrl,
        tokens = tokenProvider,
        hello = { HelloBody("dev-1", "1.0", 1, "Pixel", 34, true, "court-1", "A", 0, caps, "s9") },
        state = { StateBody(CourtMode.IDLE, 80, true, 85, 30.0, 0, 1_000, 0, -50, null) },
        outbox = outbox,
        clockEstimator = estimator,
        onCommand = {
            offsetsAtCommand.put(estimator.offsetMs())
            commands.put(it)
        },
        backoff = ReconnectBackoff(baseMs = 10, maxMs = 50),
        logger = logger,
        scheduler = scheduler,
        clockBurstSize = 2,
        clockPingSpacingMs = 10,
        clockResyncHoldMs = 300,
        onConnectionChanged = { connected, reason -> connections.put(connected).also { reasons.put(reason ?: "") } },
    )

    @After
    fun tearDown() {
        client.stop()
        scheduler.shutdownNow()
        server.shutdown()
    }

    private fun upgrade(k2: FakeK2) {
        server.enqueue(MockResponse().withWebSocketUpgrade(k2))
    }

    @Test
    fun connectSendsBearerHelloStateAndClockBurst() {
        val k2 = FakeK2()
        upgrade(k2)
        client.start()

        val request = server.takeRequest(3, TimeUnit.SECONDS)!!
        assertEquals("Bearer tok-1", request.getHeader("Authorization"))
        assertEquals("/device/v1", request.path)

        val hello = k2.received.awaitReply()
        assertEquals(C1.HELLO, hello.type)
        assertTrue(hello.body.getBoolean("rooted"))
        assertEquals("s9", hello.body.getString("activeSessionId"))

        assertEquals(85, k2.next(C1.STATE).body.getInt("chargeCapPct"))
        k2.next(C1.CLOCK_PING)
        k2.next(C1.CLOCK_PING)
        assertTrue(connections.awaitReply())
        eventually("clock burst estimate") { estimator.current() != null }
        assertTrue("offset ${estimator.offsetMs()}", estimator.offsetMs() in 900L..1_000L)
    }

    @Test
    fun malformedPongsAreDropped() {
        val logger = RecordingPhoneLogger()
        replaceClient(newClient(logger = logger))
        upgrade(FakeK2(malformedPongs = true))
        client.start()

        eventually("malformed pongs logged") {
            estimator.current() != null && synchronized(logger) { logger.warnings.size >= 2 }
        }
        assertTrue("offset ${estimator.offsetMs()}", estimator.offsetMs() in 900L..1_000L)
        assertTrue(synchronized(logger) { logger.warnings.any { it.contains("malformed clock.pong") } })
    }

    @Test
    fun unackedEventIsResentWithSameIdAfterReconnectAndClearedOnAck() {
        val first = FakeK2()
        val second = FakeK2()
        upgrade(first)
        upgrade(second)
        val id = client.sendEvent(C1.RECORDING_STARTED, JSONObject().put("sessionId", "s1"))
        assertEquals(1, outbox.size())

        client.start()
        assertEquals(id, first.next(C1.RECORDING_STARTED).id)
        first.opened.awaitReply().close(1000, "drop")

        assertEquals(id, second.next(C1.RECORDING_STARTED).id)
        second.opened.awaitReply().send(C1Envelope.ack(id, 0).encode())
        eventually("outbox drained") { outbox.size() == 0 }
        assertEquals(2, server.requestCount)
    }

    @Test
    fun commandWithDriftHoldsUntilFreshPongOrTimeout() {
        val logger = RecordingPhoneLogger()
        val k2 = FakeK2()
        replaceClient(newClient(logger = logger))
        upgrade(k2)
        client.start()
        val socket = k2.opened.awaitReply()
        eventually("first burst") {
            synchronized(logger) { logger.infos.any { it.startsWith("Clock burst done") } }
        }

        // Normal drift dispatches immediately without starting a resync.
        val pingsBefore = k2.pings.get()
        socket.send(C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), 0).encode())
        assertEquals(C1.RECORD_STOP, commands.awaitReply().type)
        offsetsAtCommand.awaitReply()
        assertEquals(pingsBefore, k2.pings.get())

        // Drifted commands hold in order until resync pong updates offset.
        k2.skewMs = 91_000
        socket.send(
            C1Envelope.create(C1.RECORD_START, JSONObject().put("sessionId", "s1"), System.currentTimeMillis() + 91_000)
                .encode(),
        )
        socket.send(
            C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), System.currentTimeMillis() + 91_000)
                .encode(),
        )
        assertEquals(C1.RECORD_START, commands.awaitReply().type)
        assertEquals(C1.RECORD_STOP, commands.awaitReply().type)
        assertTrue(offsetsAtCommand.awaitReply() in 90_900L..91_000L)

        // Hold timeout releases held commands when no pong arrives.
        k2.answerPings = false
        socket.send(
            C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), System.currentTimeMillis() + 180_000)
                .encode(),
        )
        assertEquals(C1.RECORD_STOP, commands.awaitReply().type)
        assertTrue(synchronized(logger) { logger.warnings.any { it.contains("No clock.pong") } })
    }

    @Test
    fun handshakeAuthAndTokenFailuresReconnectAndReportReasons() {
        server.enqueue(MockResponse().setResponseCode(401))
        server.enqueue(MockResponse().setResponseCode(500))
        val k2 = FakeK2()
        upgrade(k2)
        client.start()

        assertEquals("http_401", reasons.awaitReply())
        assertEquals("http_500", reasons.awaitReply())
        assertEquals(listOf(false, false, true), List(3) { connections.awaitReply() })
        k2.next(C1.HELLO)
        assertEquals(1, tokens.invalidations.get())
        assertTrue(client.isOpen)

        val failures = listOf(
            CourtAuthException("rejected", rejected = true) to "auth_rejected",
            CourtAuthException("later", rejected = false) to "auth_unavailable",
            IOException("dns") to "auth_unreachable",
        )
        for ((error, reason) in failures) {
            replaceClient(newClient(tokenProvider = FailingTokens(error)))
            client.start()
            eventually(reason) { client.lastConnectError == reason }
        }
        client.stop()
    }

    @Test
    fun notEnrolledAndGenerationFencingPreventStaleSockets() {
        val release = holdScheduler()
        client.start()
        client.stop()
        client.sendStateNow()
        release.countDown()
        drainScheduler()
        assertEquals(0, server.requestCount)

        val calls = AtomicInteger()
        val logger = RecordingPhoneLogger()
        replaceClient(
            newClient(
                webSocketUrl = { if (calls.incrementAndGet() <= 2) null else server.url("/device/v1").toString() },
                logger = logger,
            ),
        )
        val k2 = FakeK2()
        upgrade(k2)
        client.start()
        client.start()
        k2.next(C1.HELLO)
        server.takeRequest(3, TimeUnit.SECONDS)!!
        assertEquals(3, calls.get())
        assertTrue(client.connectedAtMs > 0)
        assertNull(client.lastConnectError)

        // Late handshake completion after stop closes as stale.
        val staleK2 = FakeK2()
        server.enqueue(MockResponse().withWebSocketUpgrade(staleK2).setHeadersDelay(300, TimeUnit.MILLISECONDS))
        client.stop()
        client.start()
        server.takeRequest(3, TimeUnit.SECONDS)!!
        client.stop()
        staleK2.opened.awaitReply()
        assertEquals(1000, staleK2.closed.awaitReply())
        assertFalse(client.isOpen)
    }

    @Test
    fun helloAckContractVersionAndReplySendWork() {
        val logger = RecordingPhoneLogger()
        replaceClient(newClient(logger = logger))
        val k2 = FakeK2()
        upgrade(k2)
        client.start()

        val hello = k2.next(C1.HELLO)
        val socket = k2.opened.awaitReply()
        socket.send(
            C1Envelope.create(C1.ACK, JSONObject().put("ref", hello.id).put("contractVersion", "1.28"), 0).encode(),
        )
        eventually("skewed contract recorded") {
            client.serverContractVersion == "1.28" &&
                synchronized(logger) { logger.warnings.any { "contract skew" in it } }
        }

        val reply = C1Envelope.ack("cmd-1", 123L)
        client.reply(reply)
        assertEquals(reply.id, k2.next(C1.ACK).id)

        socket.send("not json")
        val eventId = client.sendEvent(C1.RECORDING_STOPPED, JSONObject().put("sessionId", "s1"))
        k2.next(C1.RECORDING_STOPPED)
        socket.send(C1Envelope.nack(eventId, C1NackCode.BAD_REQUEST, "bad", 0).encode())
        eventually("nacked event dropped from outbox") { outbox.size() == 0 }
        assertTrue(synchronized(logger) { logger.warnings.any { "Dropping bad envelope" in it } })
    }

    private fun replaceClient(next: CourtWsClient) {
        client.stop()
        connections.clear()
        reasons.clear()
        client = next
    }

    private fun holdScheduler(): CountDownLatch {
        val latch = CountDownLatch(1)
        scheduler.execute { latch.await() }
        return latch
    }

    private fun drainScheduler() {
        val idle = CountDownLatch(1)
        scheduler.execute { idle.countDown() }
        assertTrue(idle.await(3, TimeUnit.SECONDS))
    }

    private fun eventually(what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 3_000
        while (!condition()) {
            if (System.currentTimeMillis() > deadline) {
                throw AssertionError("Timed out waiting for $what.")
            }
            Thread.sleep(10)
        }
    }
}
