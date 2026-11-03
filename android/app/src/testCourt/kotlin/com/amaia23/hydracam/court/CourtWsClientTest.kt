package com.amaia23.hydracam.court

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

    /** Fake K2 end of one connection: records envelopes, answers `clock.ping` 1000 ms ahead. */
    private inner class FakeK2(private val malformedPongs: Boolean = false) : WebSocketListener() {
        val received = LinkedBlockingQueue<C1Envelope>()
        val opened = LinkedBlockingQueue<WebSocket>()
        val closed = LinkedBlockingQueue<Int>()

        override fun onOpen(webSocket: WebSocket, response: Response) {
            opened.put(webSocket)
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val envelope = C1Envelope.decode(text)
            if (envelope.type == C1.CLOCK_PING) {
                val t0 = envelope.body.getLong("t0")
                if (malformedPongs) {
                    // No server times: read as 0 they would give a near-zero rtt and an offset of -t0.
                    webSocket.send(C1Envelope.create(C1.CLOCK_PONG, JSONObject().put("t0", t0), t0).encode())
                    val swapped = JSONObject().put("t0", t0).put("t1", t0 + 2_000).put("t2", t0 + 1_000)
                    webSocket.send(C1Envelope.create(C1.CLOCK_PONG, swapped, t0).encode())
                }
                val pong = JSONObject().put("t0", t0).put("t1", t0 + 1_000).put("t2", t0 + 1_000)
                webSocket.send(C1Envelope.create(C1.CLOCK_PONG, pong, t0 + 1_000).encode())
            }
            received.put(envelope)
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            closed.put(code)
            webSocket.close(1000, null)
        }

        fun next(type: String): C1Envelope {
            while (true) {
                val envelope = received.await()
                if (envelope.type == type) {
                    return envelope
                }
            }
        }
    }

    private inner class FakeTokens : AccessTokenProvider {
        val invalidations = AtomicInteger()

        override fun accessToken(): String = "tok-1"

        override fun invalidate() {
            invalidations.incrementAndGet()
        }
    }

    private val server = MockWebServer()
    private val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
    private val tokens = FakeTokens()
    private val estimator = ClockOffsetEstimator(burstSize = 2)
    private val commands = LinkedBlockingQueue<C1Envelope>()
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
        logger: CourtLogger = NoopCourtLogger,
    ) = CourtWsClient(
        http = http,
        webSocketUrl = webSocketUrl,
        tokens = tokenProvider,
        hello = { HelloBody("dev-1", "1.0", 1, "Pixel", 34, true, "court-1", "A", 0, caps, "s9") },
        state = { StateBody(CourtMode.IDLE, 80, true, 85, 30.0, 0, 1_000, 0, -50, null) },
        outbox = outbox,
        clockEstimator = estimator,
        onCommand = { commands.put(it) },
        backoff = ReconnectBackoff(baseMs = 10, maxMs = 50),
        logger = logger,
        scheduler = scheduler,
        clockBurstSize = 2,
        clockPingSpacingMs = 10,
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

        val hello = k2.received.await()
        assertEquals(C1.HELLO, hello.type)
        assertTrue(hello.body.getBoolean("rooted"))
        assertEquals("s9", hello.body.getString("activeSessionId"))
        assertTrue(hello.body.getJSONObject("caps").getBoolean("torch"))
        assertTrue(hello.body.getJSONObject("caps").getBoolean("speaker"))

        assertEquals(85, k2.next(C1.STATE).body.getInt("chargeCapPct"))
        k2.next(C1.CLOCK_PING)
        k2.next(C1.CLOCK_PING)
        assertTrue(connections.await())
        val deadline = System.currentTimeMillis() + 3_000
        while (estimator.current() == null && System.currentTimeMillis() < deadline) {
            Thread.sleep(10)
        }
        // pong is 1000 ms ahead of t0; the local rtt shaves a few ms off.
        assertTrue("offset ${estimator.offsetMs()}", estimator.offsetMs() in 900L..1_000L)
    }

    @Test
    fun malformedPongsAreDropped() {
        val logger = RecordingLogger()
        client = newClient(logger = logger)
        upgrade(FakeK2(malformedPongs = true))
        client.start()

        val deadline = System.currentTimeMillis() + 3_000
        while ((estimator.current() == null || logger.warnings.size < 2) && System.currentTimeMillis() < deadline) {
            Thread.sleep(10)
        }
        assertTrue("offset ${estimator.offsetMs()}", estimator.offsetMs() in 900L..1_000L)
        assertTrue(logger.warnings.any { it.contains("malformed clock.pong") })
    }

    @Test
    fun unackedEventIsResentWithSameIdAfterReconnect() {
        val first = FakeK2()
        val second = FakeK2()
        upgrade(first)
        upgrade(second)
        val id = client.sendEvent(C1.RECORDING_STARTED, JSONObject().put("sessionId", "s1"))
        assertEquals(1, outbox.size())

        client.start()
        assertEquals(id, first.next(C1.RECORDING_STARTED).id)
        first.opened.await().close(1000, "drop")

        assertEquals(id, second.next(C1.RECORDING_STARTED).id)
        second.opened.await().send(C1Envelope.ack(id, 0).encode())
        val deadline = System.currentTimeMillis() + 3_000
        while (outbox.size() > 0 && System.currentTimeMillis() < deadline) {
            Thread.sleep(10)
        }
        assertEquals(0, outbox.size())
        assertEquals(2, server.requestCount)
    }

    @Test
    fun serverCommandGoesToHandler() {
        val k2 = FakeK2()
        upgrade(k2)
        client.start()
        val socket = k2.opened.await()
        k2.next(C1.HELLO)

        socket.send(C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), 1).encode())

        val command = commands.await()
        assertEquals(C1.RECORD_STOP, command.type)
        assertEquals("s1", command.body.getString("sessionId"))
    }

    @Test
    fun http401InvalidatesTokenThenReconnects() {
        server.enqueue(MockResponse().setResponseCode(401))
        val k2 = FakeK2()
        upgrade(k2)
        client.start()

        assertFalse(connections.await())
        k2.next(C1.HELLO)
        assertEquals(1, tokens.invalidations.get())
        assertTrue(client.isOpen)
    }

    @Test
    fun otherHandshakeFailuresKeepTheTokenAndReconnect() {
        val calls = AtomicInteger()
        replaceClient(
            newClient(
                webSocketUrl = {
                    if (calls.incrementAndGet() == 1) "http://127.0.0.1:1/device/v1" else server.url("/d").toString()
                },
            ),
        )
        server.enqueue(MockResponse().setResponseCode(500))
        val k2 = FakeK2()
        upgrade(k2)
        client.start()

        k2.next(C1.HELLO)
        val failures = listOf(reasons.await(), reasons.await())
        assertEquals("ConnectException", failures[0])
        assertEquals("http_500", failures[1])
        assertEquals(listOf(false, false, true), listOf(connections.await(), connections.await(), connections.await()))
        assertEquals(0, tokens.invalidations.get())
    }

    @Test
    fun notEnrolledRetriesUntilAUrlExistsAndStartIsIdempotent() {
        val calls = AtomicInteger()
        val logger = RecordingLogger()
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
        assertEquals(3, calls.get())
        assertEquals(2, synchronized(logger) { logger.infos.count { it.endsWith("(not_enrolled).") } })
        assertTrue(client.connectedAtMs > 0)
        assertNull(client.lastConnectError)
    }

    @Test
    fun tokenFailuresAreReportedAndRetriedWithoutConnecting() {
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
        assertEquals(0, server.requestCount)
    }

    @Test
    fun connectQueuedBeforeStopOpensNothing() {
        val release = holdScheduler()
        client.start()
        client.stop()
        client.sendStateNow()
        release.countDown()

        drainScheduler()
        assertEquals(0, server.requestCount)
        assertFalse(client.isOpen)
    }

    @Test
    fun stopDuringTheTokenFetchOpensNoSocket() {
        lateinit var stopping: CourtWsClient
        val tokenThenStop = object : AccessTokenProvider {
            override fun accessToken(): String = "tok-1".also { stopping.stop() }

            override fun invalidate() = Unit
        }
        stopping = newClient(tokenProvider = tokenThenStop)
        replaceClient(stopping)

        client.start()

        assertEquals("stopped", reasons.await())
        drainScheduler()
        assertEquals(0, server.requestCount)
    }

    @Test
    fun failureAfterARestartDoesNotScheduleAStaleReconnect() {
        val calls = AtomicInteger()
        lateinit var flaky: CourtWsClient
        flaky = newClient(
            webSocketUrl = {
                when (calls.incrementAndGet()) {
                    1 -> null.also { flaky.stop() }
                    2 -> null.also { flaky.restart() }
                    else -> server.url("/device/v1").toString()
                }
            },
        )
        replaceClient(flaky)
        val k2 = FakeK2()
        upgrade(k2)

        client.start()
        assertEquals("stopped", reasons.await())
        drainScheduler()
        assertEquals(1, calls.get())
        client.start()

        k2.next(C1.HELLO)
        assertEquals(3, calls.get())
        assertEquals(1, server.requestCount)
    }

    @Test
    fun handshakeThatCompletesAfterStopIsClosedAsStale() {
        val k2 = FakeK2()
        server.enqueue(MockResponse().withWebSocketUpgrade(k2).setHeadersDelay(300, TimeUnit.MILLISECONDS))
        client.start()
        server.takeRequest(3, TimeUnit.SECONDS)!!
        client.stop()

        k2.opened.await().send(C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), 1).encode())

        assertEquals(1000, k2.closed.await())
        assertFalse(client.isOpen)
        assertEquals(listOf(false), connections.toList())
        assertTrue(commands.isEmpty())
    }

    @Test
    fun badFramesAndUnknownRefsAreIgnored() {
        val logger = RecordingLogger()
        replaceClient(newClient(logger = logger))
        val k2 = FakeK2()
        upgrade(k2)
        val nacked = client.sendEvent(C1.RECORDING_STARTED, JSONObject().put("sessionId", "s1"))
        val pending = client.sendEvent(C1.RECORDING_STOPPED, JSONObject().put("sessionId", "s1"))
        client.sendStateNow()
        client.start()
        val socket = k2.opened.await()
        k2.next(C1.STATE)

        socket.send("not json")
        socket.send(C1Envelope.ack("unknown", 0).encode())
        socket.send(C1Envelope.nack("unknown", C1NackCode.BAD_REQUEST, null, 0).encode())
        socket.send(C1Envelope.nack(nacked, C1NackCode.BAD_REQUEST, "no session", 0).encode())
        socket.send(C1Envelope.create(C1.RECORD_STOP, JSONObject().put("sessionId", "s1"), 1).encode())
        commands.await()
        client.sendStateNow()

        k2.next(C1.STATE)
        assertEquals(listOf(pending), outbox.pendingIds())
        val warnings = synchronized(logger) { logger.warnings.toList() }
        assertEquals(1, warnings.count { it.startsWith("Dropping bad envelope") })
        assertEquals(listOf("K2 nacked event $nacked: ${C1NackCode.BAD_REQUEST}"), warnings.filter { "nacked" in it })
    }

    private class FailingTokens(private val error: IOException) : AccessTokenProvider {
        override fun accessToken(): String = throw error

        override fun invalidate() = Unit
    }

    private fun CourtWsClient.restart() {
        stop()
        start()
    }

    /** Swaps in [next] after stopping the default client, which never started (no socket to close). */
    private fun replaceClient(next: CourtWsClient) {
        client.stop()
        connections.clear()
        reasons.clear()
        client = next
    }

    /** Blocks the client's scheduler thread until the returned latch is counted down. */
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
