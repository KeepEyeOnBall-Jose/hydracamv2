package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.security.MessageDigest

class TsSegmenterTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val frameUs = 33_333L
    private val serverBaseMs = 1_700_000_000_000L
    private val seqStore = InMemorySegmentSeqStore()
    private val segments = mutableListOf<SegmentRecord>()
    private var syncRequests = 0
    private lateinit var storage: CourtStorage

    @Before
    fun setUp() {
        storage = CourtStorage(temp.newFolder("court"))
    }

    private fun segmenter(hasAudio: Boolean = false, estimate: ClockEstimate? = ClockEstimate(1_000, 12, 0)) =
        TsSegmenter(
            sessionId = "s1",
            slot = "A",
            tier = C1.TIER_PROXY,
            directory = storage.tierDir("s1", C1.TIER_PROXY),
            sidecar = JsonlAppender(storage.sidecar("s1")),
            seqStore = seqStore,
            timebase = SessionTimebase { ptsUs -> serverBaseMs + ptsUs / 1_000 },
            segmentDurationUs = 6_000_000,
            frameDurationUs = frameUs,
            hasAudio = hasAudio,
            clockEstimate = { estimate },
            onSegment = { segments += it },
            requestSyncFrame = { syncRequests += 1 },
            clock = FakeClock(),
        )

    /** 30 fps, IDR every 30 frames (first IDR at frame 30), frames [from, until). */
    private fun feed(target: TsSegmenter, from: Int, until: Int) {
        for (index in from until until) {
            target.onVideoFrame(
                index * frameUs,
                ByteArray(200) { index.toByte() },
                isKeyframe =
                index % 30 == 0 && index > 0,
            )
        }
    }

    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toHex()

    @Test
    fun cutsOnIdrNearSixSecondsAndWritesSidecar() {
        val target = segmenter()
        target.onVideoConfig(byteArrayOf(0, 0, 0, 1, 0x67))
        feed(target, 0, 400)

        // Frames 0..29 come before the first IDR and are dropped.
        assertEquals(listOf(0L, 1L), segments.map { it.seq })
        assertEquals(180, segments[0].frames)
        assertEquals(5_999L, segments[0].durationMs)
        assertEquals(serverBaseMs + 30 * frameUs / 1_000, segments[0].mediaStartServerMs)
        assertEquals(2, syncRequests)

        assertEquals(2L, target.finish())
        assertEquals(2L, target.finish())
        assertEquals(3, segments.size)
        assertEquals(10, segments[2].frames)
        assertEquals((10 * frameUs) / 1_000, segments[2].durationMs)
        assertEquals(2L, seqStore.lastSeq("s1", C1.TIER_PROXY))

        val dir = storage.tierDir("s1", C1.TIER_PROXY)
        assertEquals(listOf("000000.ts", "000001.ts", "000002.ts"), dir.list()!!.sorted())
        segments.forEach { record ->
            assertEquals(sha256(record.file), record.sha256)
            assertEquals(record.file.length(), record.bytes)
            assertEquals(0, record.bytes % MpegTsMuxer.PACKET_SIZE)
            // Each file starts with PAT (pid 0) then PMT.
            val head = record.file.readBytes()
            assertEquals(0x47.toByte(), head[0])
            assertEquals(0, ((head[1].toInt() and 0x1F) shl 8) or (head[2].toInt() and 0xFF))
        }

        val lines = storage.sidecar("s1").readLines().map { JSONObject(it) }
        assertEquals(3, lines.size)
        assertEquals("proxy/000001.ts", lines[1].getString("file"))
        assertEquals(1L, lines[1].getLong("seq"))
        assertEquals(1_000L, lines[1].getLong("offsetMs"))
        assertEquals(12L, lines[1].getLong("rttMs"))
        assertEquals(segments[1].sha256, lines[1].getString("sha256"))
    }

    @Test
    fun seqContinuesFromStoreAndStalePartIsRemoved() {
        seqStore.commitSeq("s1", C1.TIER_PROXY, 4)
        val dir = storage.tierDir("s1", C1.TIER_PROXY)
        dir.mkdirs()
        val stale = File(dir, "000005.ts.part")
        stale.writeText("partial")

        val target = segmenter(estimate = null)
        assertFalse(stale.exists())
        feed(target, 30, 40)
        target.finish()

        assertEquals(5L, segments.single().seq)
        assertTrue(File(dir, "000005.ts").isFile)
        val line = JSONObject(storage.sidecar("s1").readLines().single())
        assertEquals(-1L, line.getLong("rttMs"))
        assertEquals(0L, line.getLong("offsetMs"))
    }

    @Test
    fun openSegmentIsOnlyPartUntilClosed() {
        val target = segmenter()
        feed(target, 30, 40)
        val dir = storage.tierDir("s1", C1.TIER_PROXY)

        assertEquals(listOf("000000.ts.part"), dir.list()!!.toList())
        assertEquals(-1L, target.lastSeq)

        target.abort()

        assertTrue(dir.list()!!.isEmpty())
        assertTrue(segments.isEmpty())
        assertEquals(-1L, seqStore.lastSeq("s1", C1.TIER_PROXY))
        // After abort nothing more is written.
        feed(target, 60, 70)
        assertTrue(dir.list()!!.isEmpty())
    }

    @Test
    fun finishWithoutFramesReturnsNone() {
        val target = segmenter()
        feed(target, 0, 20)

        assertEquals(-1L, target.finish())
        assertTrue(segments.isEmpty())
    }

    @Test
    fun audioIsMuxedOnlyAfterVideoOpens() {
        val target = segmenter(hasAudio = true)
        target.onAudioFrame(0, ByteArray(100))
        feed(target, 30, 31)
        target.onAudioFrame(30 * frameUs + 1_000, ByteArray(100))
        target.finish()

        val bytes = segments.single().file.readBytes()
        val pids = (0 until bytes.size / MpegTsMuxer.PACKET_SIZE).map { index ->
            val offset = index * MpegTsMuxer.PACKET_SIZE
            ((bytes[offset + 1].toInt() and 0x1F) shl 8) or (bytes[offset + 2].toInt() and 0xFF)
        }
        assertEquals(1, pids.count { it == MpegTsMuxer.AUDIO_PID })
    }

    private fun audioPackets(file: File): Int {
        val bytes = file.readBytes()
        return (0 until bytes.size / MpegTsMuxer.PACKET_SIZE).count { index ->
            val offset = index * MpegTsMuxer.PACKET_SIZE
            (((bytes[offset + 1].toInt() and 0x1F) shl 8) or (bytes[offset + 2].toInt() and 0xFF)) ==
                MpegTsMuxer.AUDIO_PID
        }
    }

    @Test
    fun audioIsDroppedWithoutAnAudioTrackOrBeforeTheTimebase() {
        val videoOnly = segmenter(hasAudio = false)
        feed(videoOnly, 30, 31)
        videoOnly.onAudioFrame(30 * frameUs + 1_000, ByteArray(100))
        videoOnly.finish()
        assertEquals(0, audioPackets(segments.single().file))

        segments.clear()
        val withAudio = segmenter(hasAudio = true)
        feed(withAudio, 60, 61)
        withAudio.onAudioFrame(60 * frameUs - 1, ByteArray(100))
        withAudio.finish()
        withAudio.onAudioFrame(61 * frameUs, ByteArray(100))
        assertEquals(0, audioPackets(segments.single().file))
    }

    @Test
    fun abortBeforeAnyFrameIsHarmless() {
        val target = segmenter()
        target.abort()

        assertEquals(-1L, target.finish())
        assertTrue(segments.isEmpty())
    }

    @Test
    fun failedRenameKeepsSeqUncommitted() {
        val dir = storage.tierDir("s1", C1.TIER_PROXY)
        File(dir, "000000.ts").apply {
            mkdirs()
            File(this, "occupied").writeText("x")
        }
        val target = segmenter()
        feed(target, 30, 40)

        assertThrows(IOException::class.java) { target.finish() }
        assertEquals(-1L, seqStore.lastSeq("s1", C1.TIER_PROXY))
        assertTrue(segments.isEmpty())
        assertFalse(storage.sidecar("s1").exists())
    }

    @Test
    fun unwritableDirectoryFailsOnTheFirstSegment() {
        val dir = storage.tierDir("s1", C1.TIER_PROXY)
        dir.parentFile.mkdirs()
        dir.writeText("a file where the tier directory should be")
        val target = segmenter()

        assertThrows(IOException::class.java) { feed(target, 30, 31) }
    }
}
