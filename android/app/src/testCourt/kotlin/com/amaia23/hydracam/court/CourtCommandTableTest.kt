package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class CourtCommandTableTest {
    private val replies = LinkedBlockingQueue<C1Envelope>()
    private val calls = AtomicInteger()
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
    )
    private val table = CourtCommandTable(handlers, { replies.put(it) }, deadlineMs = 200)

    @After
    fun tearDown() {
        table.shutdown()
    }

    private fun command(type: String, id: String = "cmd-$type") =
        C1Envelope(id = id, type = type, ts = 1, body = JSONObject())

    @Test
    fun ackReferencesTheCommand() {
        table.dispatch(command(C1.RECORD_STOP, "c1"))

        val reply = replies.await()
        assertEquals(C1.ACK, reply.type)
        assertEquals("c1", reply.body.getString("ref"))
    }

    @Test
    fun duplicateIdReplaysCachedReplyWithoutRerunning() {
        table.dispatch(command(C1.RECORD_STOP, "c1"))
        table.dispatch(command(C1.RECORD_STOP, "c1"))
        table.dispatch(command(C1.RECORD_STOP, "c2"))

        val first = replies.await()
        val second = replies.await()
        val third = replies.await()
        assertEquals(first, second)
        assertEquals("c2", third.body.getString("ref"))
        assertEquals(2, calls.get())
    }

    @Test
    fun handlerNackIsForwarded() {
        table.dispatch(command(C1.RECORD_START))

        val reply = replies.await()
        assertEquals(C1.NACK, reply.type)
        assertEquals(C1NackCode.NOT_ROOTED, reply.body.getString("code"))
    }

    @Test
    fun unknownCommandIsUnsupported() {
        table.dispatch(command(C1.APP_UPDATE))

        assertEquals(C1NackCode.UNSUPPORTED, replies.await().body.getString("code"))
    }

    @Test
    fun slowHandlerIsNackedWithinDeadline() {
        val startedAt = System.nanoTime()
        table.dispatch(command(C1.SIGNAL_EMIT))

        val reply = replies.await(1_500)
        val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)
        assertEquals(C1NackCode.TIMEOUT, reply.body.getString("code"))
        assertEquals(true, elapsedMs < 1_500)
    }

    @Test
    fun badBodyIsBadRequestAndCrashIsInternal() {
        table.dispatch(command(C1.RECORD_PREPARE))
        table.dispatch(command(C1.SNAPSHOT))

        val bad = replies.await()
        assertEquals(C1NackCode.BAD_REQUEST, bad.body.getString("code"))
        assertEquals("Missing sessionId.", bad.body.getString("reason"))
        assertEquals(C1NackCode.INTERNAL, replies.await().body.getString("code"))
    }

    @Test
    fun commandsAnswerInArrivalOrder() {
        for (index in 0 until 20) {
            table.dispatch(command(C1.RECORD_STOP, "c$index"))
        }
        for (index in 0 until 20) {
            assertEquals("c$index", replies.await().body.getString("ref"))
        }
        assertNull(replies.poll(100, TimeUnit.MILLISECONDS))
    }
}
