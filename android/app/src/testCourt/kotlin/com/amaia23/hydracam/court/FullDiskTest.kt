package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException

/** Full disk: a failed write commits nothing, and a torn sidecar line never hides a later segment. */
class FullDiskTest {
    @get:Rule
    val temp = TemporaryFolder()

    private lateinit var storage: CourtStorage

    @Before
    fun setUp() {
        storage = CourtStorage(temp.newFolder("court"))
    }

    private fun record(seq: Long) = SegmentRecord(
        sessionId = "s1",
        slot = "A",
        tier = C1.TIER_PROXY,
        seq = seq,
        file = File(storage.tierDir("s1", C1.TIER_PROXY), "%06d.ts".format(seq)),
        bytes = 188,
        sha256 = "ab".repeat(32),
        mediaStartServerMs = 1_700_000_000_000L + seq * 6_000,
        durationMs = 6_000,
        frames = 180,
        offsetMs = 0,
        rttMs = 12,
    )

    @Test
    fun aTornSidecarLineDoesNotSwallowTheNextSegment() {
        val sidecar = JsonlAppender(storage.sidecar("s1"))
        sidecar.append(record(0).toSidecarJson(1L))
        // ENOSPC mid-append left half a line with no newline.
        storage.sidecar("s1").appendText(record(1).toSidecarJson(1L).toString().take(40))
        sidecar.append(record(2).toSidecarJson(1L))

        val logger = RecordingLogger()
        val seqs = SegmentSidecarReader(storage, logger).readAll().map { it.seq }

        assertEquals(listOf(0L, 2L), seqs)
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun aSidecarWriteFailureCommitsNoSegment() {
        val seqStore = InMemorySegmentSeqStore()
        val segments = mutableListOf<SegmentRecord>()
        // A directory where the sidecar file should be makes every append throw, as a full disk does.
        val blocked = storage.sidecar("s1").apply { mkdirs() }
        val segmenter = TsSegmenter(
            sessionId = "s1",
            slot = "A",
            tier = C1.TIER_PROXY,
            directory = storage.tierDir("s1", C1.TIER_PROXY),
            sidecar = JsonlAppender(blocked),
            seqStore = seqStore,
            timebase = SessionTimebase { ptsUs -> ptsUs / 1_000 },
            segmentDurationUs = 6_000_000,
            frameDurationUs = FRAME_US,
            hasAudio = false,
            clockEstimate = { null },
            onSegment = { segments += it },
        )

        assertThrows(IOException::class.java) {
            for (index in 0 until 400) {
                segmenter.onVideoFrame(index * FRAME_US, ByteArray(100), isKeyframe = index % 30 == 0)
            }
        }

        assertTrue(segments.isEmpty())
        assertEquals(-1L, seqStore.lastSeq("s1", C1.TIER_PROXY))
        assertEquals(-1L, segmenter.lastSeq)
    }

    private companion object {
        const val FRAME_US = 33_333L
    }
}
