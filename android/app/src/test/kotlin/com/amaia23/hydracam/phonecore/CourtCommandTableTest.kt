package com.amaia23.hydracam.phonecore

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class CourtCommandTableTest {
    private val replies = LinkedBlockingQueue<C1Envelope>()
    private val calls = AtomicInteger()
    private val clock = FakePhoneClock(1_000L)
    private val logger = RecordingPhoneLogger()
    private val handlers = mapOf(
        C1.RECORD_STOP to CommandHandler {
            calls.incrementAndGet()
            CommandResult.Ack
        },
        C1.RECORD_START to CommandHandler { CommandResult.Nack(C1NackCode.NOT_ROOTED, "no root") },
        C1.SIGNAL_EMIT to CommandHandler {
            Thread.sleep(2_000)
            CommandResult.Ack
        },
        C1.RECORD_PREPARE to CommandHandler { throw C1ProtocolException("Missing sessionId.") },
        C1.SNAPSHOT to CommandHandler { throw IllegalStateException("boom") },
        C1.MASTERS_UPLOAD to CommandHandler {
            MastersUpload.fromJson(it.body)
            CommandResult.Ack
        },
    )
    private val table = CourtCommandTable(
        handlers = handlers,
        reply = { replies.put(it) },
        clock = clock,
        logger = logger,
        deadlineMs = 200,
    )

    @After
    fun tearDown() {
        table.shutdown()
    }

    private fun command(type: String, id: String = "cmd-$type", body: JSONObject = JSONObject()) =
        C1Envelope(id = id, type = type, ts = 1, body = body)

    private fun masters(id: String, fromServerMs: Long, toServerMs: Long?) = command(
        C1.MASTERS_UPLOAD,
        id,
        JSONObject()
            .put("sessionId", "s1")
            .put("fromServerMs", fromServerMs)
            .put("toServerMs", toServerMs ?: JSONObject.NULL)
            .put("uploadGrant", "g")
            .put("ingestUrl", "https://k3.example"),
    )

    @Test
    fun ackReferencesTheCommandAndStampsClock() {
        table.dispatch(command(C1.RECORD_STOP, "c1"))

        val reply = replies.awaitReply()
        assertEquals(C1.ACK, reply.type)
        assertEquals(1_000L, reply.ts)
        assertEquals("c1", reply.body.getString("ref"))
    }

    @Test
    fun duplicateIdReplaysCachedReplyWithoutRerunning() {
        table.dispatch(command(C1.RECORD_STOP, "c1"))
        table.dispatch(command(C1.RECORD_STOP, "c1"))
        table.dispatch(command(C1.RECORD_STOP, "c2"))

        val first = replies.awaitReply()
        val second = replies.awaitReply()
        val third = replies.awaitReply()
        assertEquals(first, second)
        assertEquals("c2", third.body.getString("ref"))
        assertEquals(2, calls.get())
        assertTrue(logger.infos.any { it.contains("Duplicate ${C1.RECORD_STOP} id=c1") })
    }

    @Test
    fun handlerNackAndUnknownCommandAreForwarded() {
        table.dispatch(command(C1.RECORD_START))
        table.dispatch(command(C1.APP_UPDATE))

        val nack = replies.awaitReply()
        assertEquals(C1.NACK, nack.type)
        assertEquals(C1NackCode.NOT_ROOTED, nack.body.getString("code"))
        assertEquals(C1NackCode.UNSUPPORTED, replies.awaitReply().body.getString("code"))
    }

    @Test
    fun slowHandlerIsNackedWithinDeadline() {
        val startedAt = System.nanoTime()
        table.dispatch(command(C1.SIGNAL_EMIT))

        val reply = replies.awaitReply(1_500)
        val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)
        assertEquals(C1NackCode.TIMEOUT, reply.body.getString("code"))
        assertTrue(elapsedMs < 1_500)
    }

    @Test
    fun protocolExceptionCrashAndRangeFailureMapToExpectedNackCodes() {
        table.dispatch(command(C1.RECORD_PREPARE))
        table.dispatch(command(C1.SNAPSHOT))
        table.dispatch(masters("inverted", 2_000, 1_999))
        table.dispatch(masters("open", 2_000, null))

        val bad = replies.awaitReply()
        assertEquals(C1NackCode.BAD_REQUEST, bad.body.getString("code"))
        assertEquals("Missing sessionId.", bad.body.getString("reason"))
        assertEquals(C1NackCode.INTERNAL, replies.awaitReply().body.getString("code"))
        assertEquals(C1NackCode.BAD_RANGE, replies.awaitReply().body.getString("code"))
        assertEquals(C1.ACK, replies.awaitReply().type)
        assertTrue(logger.warnings.any { it.contains("Handler for ${C1.SNAPSHOT} failed.") })
    }

    @Test
    fun commandsAnswerInArrivalOrderAndEvictOldCacheEntries() {
        val smallCacheTable = CourtCommandTable(
            handlers = handlers,
            reply = { replies.put(it) },
            cacheSize = 2,
        )
        try {
            for (index in 0 until 10) {
                smallCacheTable.dispatch(command(C1.RECORD_STOP, "c$index"))
            }
            for (index in 0 until 10) {
                assertEquals("c$index", replies.awaitReply().body.getString("ref"))
            }
            assertNull(replies.poll(100, TimeUnit.MILLISECONDS))

            smallCacheTable.dispatch(command(C1.RECORD_STOP, "c0"))
            assertEquals("c0", replies.awaitReply().body.getString("ref"))
            assertEquals(11, calls.get())
        } finally {
            smallCacheTable.shutdown()
        }
    }
}
