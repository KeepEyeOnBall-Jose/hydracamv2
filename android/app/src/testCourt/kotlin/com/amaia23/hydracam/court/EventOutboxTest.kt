package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class EventOutboxTest {
    @get:Rule
    val temp = TemporaryFolder()

    private fun event(seq: Int) = C1Envelope.create(C1.RECORDING_SEGMENT, JSONObject().put("seq", seq), 1_000L + seq)

    @Test
    fun pendingEventsSurviveRestartInOrder() {
        val dir = temp.newFolder("outbox")
        val outbox = EventOutbox(dir)
        val events = (0 until 5).map { event(it) }
        events.forEach { outbox.add(it) }
        outbox.ack(events[1].id)

        val reloaded = EventOutbox(dir)

        assertEquals(listOf(0, 2, 3, 4).map { events[it].id }, reloaded.pendingIds())
        val due = reloaded.takeDue(nowMs = 0, resendAfterMs = 10_000)
        assertEquals(events[2].body.getInt("seq"), due[1].body.getInt("seq"))
        // New entries sort after reloaded ones.
        val later = event(9)
        reloaded.add(later)
        assertEquals(later.id, EventOutbox(dir).pendingIds().last())
    }

    @Test
    fun ackDeletesTheFile() {
        val dir = temp.newFolder("outbox")
        val outbox = EventOutbox(dir)
        val envelope = event(0)
        outbox.add(envelope)
        assertEquals(1, dir.listFiles()!!.count { it.name.endsWith(".json") })

        assertTrue(outbox.ack(envelope.id))
        assertFalse(outbox.ack(envelope.id))
        assertEquals(0, dir.listFiles()!!.size)
    }

    @Test
    fun takeDueWaitsForResendWindowAndReconnectMakesAllDue() {
        val outbox = EventOutbox(directory = null)
        outbox.add(event(0))

        assertEquals(1, outbox.takeDue(nowMs = 100, resendAfterMs = 10_000).size)
        assertTrue(outbox.takeDue(nowMs = 5_000, resendAfterMs = 10_000).isEmpty())
        assertEquals(1, outbox.takeDue(nowMs = 10_100, resendAfterMs = 10_000).size)

        outbox.markAllUnsent()
        assertEquals(1, outbox.takeDue(nowMs = 10_200, resendAfterMs = 10_000).size)
    }

    @Test
    fun fullOutboxDropsOldest() {
        val dir = temp.newFolder("outbox")
        val outbox = EventOutbox(dir, maxEntries = 3)
        val events = (0 until 5).map { event(it) }
        events.forEach { outbox.add(it) }

        assertEquals(events.drop(2).map { it.id }, outbox.pendingIds())
        assertEquals(3, dir.listFiles()!!.size)
    }

    @Test
    fun unreadableFileIsDropped() {
        val dir = temp.newFolder("outbox")
        java.io.File(dir, "000000000000-bad.json").writeText("{not json")

        val outbox = EventOutbox(dir)

        assertEquals(0, outbox.size())
        assertEquals(0, dir.listFiles()!!.size)
    }
}
