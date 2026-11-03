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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class CourtWsClientTest {
    @get:Rule
    val temp = TemporaryFolder()

    /** Fake K2 end of one connection: records envelopes, answers `clock.ping` 1000 ms ahead. */
    private inner class FakeK2 : WebSocketListener() {
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
    private lateinit var scheduler: ScheduledExecutorService
    private lateinit var outbox: EventOutbox
    private lateinit var client: CourtWsClient

    private val caps = CourtCaps("1080p", listOf(30, 60), hevc = false, encoders = 2, torch = true, speaker = true)

    @Before
    fun setUp() {
        server.start()
        scheduler = Executors.newSingleThreadScheduledExecutor()
        outbox = EventOutbox(temp.newFolder("outbox"))
        client = CourtWsClient(
            http = http,
            webSocketUrl = { server.url("/device/v1").toString() },
            tokens = tokens,
            hello = { HelloBody("dev-1", "1.0", 1, "Pixel", 34, true, "court-1", "A", 0, caps, "s9") },
            state = { StateBody(CourtMode.IDLE, 80, true, 85, 30.0, 0, 1_000, 0, -50, null) },
            outbox = outbox,
            clockEstimator = estimator,
            onCommand = { commands.put(it) },
            backoff = ReconnectBackoff(baseMs = 10, maxMs = 50),
            scheduler = scheduler,
            clockBurstSize = 2,
            clockPingSpacingMs = 10,
            onConnectionChanged = { connected, _ -> connections.put(connected) },
        )
    }

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
}
