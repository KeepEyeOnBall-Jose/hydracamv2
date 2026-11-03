package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SegmentSidecarReaderTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val logger = RecordingLogger()
    private lateinit var storage: CourtStorage
    private lateinit var reader: SegmentSidecarReader

    @Before
    fun setUp() {
        storage = CourtStorage(temp.newFolder("court"))
        reader = SegmentSidecarReader(storage, logger)
    }

    private fun record(sessionId: String = "s1", tier: String = C1.TIER_PROXY, seq: Long = 3) = SegmentRecord(
        sessionId = sessionId,
        slot = "A",
        tier = tier,
        seq = seq,
        file = File(storage.tierDir(sessionId, tier), "%06d.ts".format(seq)),
        bytes = 188,
        sha256 = "ab".repeat(32),
        mediaStartServerMs = 1_700_000_000_000L,
        durationMs = 6_000,
        frames = 180,
        offsetMs = -40,
        rttMs = 12,
    )

    private fun line(edit: JSONObject.() -> Unit = {}): String = record().toSidecarJson(1L).apply(edit).toString()

    @Test
    fun validLineRoundTrips() {
        val parsed = reader.parse(storage.sessionDir("s1"), line())

        assertEquals(record(), parsed)
    }

    @Test
    fun everyInvalidFieldRejectsTheLine() {
        val dir = storage.sessionDir("s1")
        val invalid = mapOf<String, JSONObject.() -> Unit>(
            "blank session" to { put("sessionId", "") },
            "other session" to { put("sessionId", "s2") },
            "blank slot" to { put("slot", " ") },
            "unknown tier" to { put("tier", "raw") },
            "missing seq" to { remove("seq") },
            "path outside tier" to { put("file", "proxy/../../escape.ts") },
            "empty file" to { put("bytes", 0) },
            "uppercase hash" to { put("sha256", "AB".repeat(32)) },
            "short hash" to { put("sha256", "ab") },
            "negative media start" to { put("mediaStartServerMs", -1) },
            "negative duration" to { put("durationMs", -5) },
        )
        invalid.forEach { (case, edit) -> assertNull(case, reader.parse(dir, line(edit))) }
        assertNull("not json", reader.parse(dir, "{oops"))
    }

    @Test
    fun readAllSkipsAndCountsBadLinesPerSession() {
        val master = record(tier = C1.TIER_MASTER, seq = 0).toSidecarJson(2L).toString()
        storage.sidecar("s1").apply {
            parentFile.mkdirs()
            writeText(listOf(line(), "", "garbage", master).joinToString("\n"))
        }
        storage.sessionDir("s2").mkdirs()
        File(storage.root, "sessions/stray.txt").writeText("not a session")

        val records = reader.readAll()

        assertEquals(listOf(C1.TIER_PROXY to 3L, C1.TIER_MASTER to 0L), records.map { it.tier to it.seq })
        assertEquals(listOf("Skipped 1 invalid line(s) in s1/segments.jsonl."), logger.warnings)
    }

    @Test
    fun noSessionsDirectoryReadsNothing() {
        assertTrue(reader.readAll().isEmpty())
        assertTrue(storage.sessionDirs().isEmpty())
        assertNotNull(storage.signalsLog().parentFile)
    }

    @Test
    fun unsafeSessionIdsStayInsideTheSessionsDirectory() {
        val dir = storage.sessionDir("../../etc/passwd")

        assertEquals(File(storage.root, "sessions"), dir.parentFile)
        assertEquals(".._.._etc_passwd", dir.name)
    }
}
