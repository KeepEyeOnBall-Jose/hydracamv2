package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

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
        assertTrue(outbox.ack(outbox.pendingIds().single()))
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
    fun unreadableFilesAreDropped() {
        val dir = temp.newFolder("outbox")
        File(dir, "000000000000-bad.json").writeText("{not json")
        File(dir, "000000000001-v9.json").writeText("""{"order":1,"envelope":{"v":9,"id":"x","type":"t"}}""")
        File(dir, "000000000002-dir.json").mkdirs()
        val logger = RecordingLogger()

        val outbox = EventOutbox(dir, logger = logger)

        assertEquals(0, outbox.size())
        assertEquals(0, dir.listFiles()!!.size)
        assertEquals(3, logger.warnings.count { it.startsWith("Dropping unreadable outbox file") })
    }

    @Test
    fun missingDirectoryIsCreatedOnTheFirstEvent() {
        val dir = File(temp.root, "later/outbox")
        val outbox = EventOutbox(dir)
        assertEquals(0, outbox.size())

        outbox.add(event(0))

        assertEquals(1, dir.listFiles()!!.size)
    }

    @Test
    fun unwritableDirectoryKeepsEventsInMemory() {
        val dir = temp.newFolder("outbox")
        val logger = RecordingLogger()
        val outbox = EventOutbox(dir, logger = logger)
        dir.setWritable(false)
        try {
            assumeFalse("running as a user that ignores permissions", dir.canWrite())

            outbox.add(event(0))

            assertEquals(1, outbox.size())
            assertEquals(1, logger.warnings.size)
        } finally {
            dir.setWritable(true)
        }
    }
}
