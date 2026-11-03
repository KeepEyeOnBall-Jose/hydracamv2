package com.amaia23.hydracam.court

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

/** A process killed mid-segment leaves `<seq>.ts.part` per tier; the next run closes it as a short segment. */
class TsPartRecoveryTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val frameUs = 33_333L
    private val serverBaseMs = 1_700_000_000_000L
    private val seqStore = InMemorySegmentSeqStore()
    private val segments = mutableListOf<SegmentRecord>()
    private val gaps = mutableListOf<SegmentGap>()
    private lateinit var storage: CourtStorage

    @Before
    fun setUp() {
        storage = CourtStorage(temp.newFolder("court"))
    }

    private fun segmenter(tier: String, timebase: SessionTimebase) = TsSegmenter(
        sessionId = "s1",
        slot = "A",
        tier = tier,
        directory = storage.tierDir("s1", tier),
        sidecar = JsonlAppender(storage.sidecar("s1")),
        seqStore = seqStore,
        timebase = timebase,
        segmentDurationUs = 6_000_000,
        frameDurationUs = frameUs,
        hasAudio = false,
        clockEstimate = { ClockEstimate(1_000, 12) },
        onSegment = { segments += it },
        onGap = { gaps += it },
        clock = FakeClock(),
    )

    private fun timebase() = SessionTimebase { ptsUs -> serverBaseMs + ptsUs / 1_000 }

    private fun recovery(tier: String) = TsPartRecovery(
        sessionId = "s1",
        slot = "A",
        tier = tier,
        directory = storage.tierDir("s1", tier),
        sidecar = JsonlAppender(storage.sidecar("s1")),
        seqStore = seqStore,
        clock = FakeClock(),
    )

    /** 30 fps, IDR every 180 frames from frame 0, frames [from, until), to every segmenter. */
    private fun feed(targets: Collection<TsSegmenter>, from: Int, until: Int) {
        for (index in from until until) {
            targets.forEach { it.onVideoFrame(index * frameUs, ByteArray(200) { index.toByte() }, index % 180 == 0) }
        }
    }

    /** Both tiers record 180 + 45 frames, then the process dies without closing anything. */
    private fun crashMidSecondSegment() {
        val timebase = timebase()
        val tiers = C1.TIERS.associateWith { segmenter(it, timebase) }
        feed(tiers.values, 0, 225)
        assertEquals(2, segments.size)
        segments.clear()
    }

    private fun part(tier: String, seq: Int = 1) = File(storage.tierDir("s1", tier), "%06d.ts.part".format(seq))

    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toHex()

    private fun assertRecoveredSecondSegment(record: SegmentRecord, tier: String) {
        assertEquals(tier, record.tier)
        assertEquals(1L, record.seq)
        // The last frame may be torn, so it is cut: 44 of 45 frames survive.
        assertEquals(44, record.frames)
        assertEquals(44 * frameUs / 1_000, record.durationMs, 1.0)
        assertEquals(serverBaseMs + 180 * frameUs / 1_000, record.mediaStartServerMs)
        assertEquals(1_000L, record.offsetMs)
        assertEquals(12L, record.rttMs)
        assertEquals(File(storage.tierDir("s1", tier), "000001.ts"), record.file)
        assertEquals(record.file.length(), record.bytes)
        assertEquals(0, record.bytes % MpegTsMuxer.PACKET_SIZE)
        assertEquals(sha256(record.file), record.sha256)
        assertEquals(1L, seqStore.lastSeq("s1", tier))
        assertEquals(listOf("000000.ts", "000001.ts"), storage.tierDir("s1", tier).list()!!.sorted())
    }

    private fun assertEquals(expected: Long, actual: Long, tolerance: Double) =
        assertEquals(expected.toDouble(), actual.toDouble(), tolerance)

    @Test
    fun resumeAfterCrashClosesBothTiersPartialSegments() {
        crashMidSecondSegment()
        // The kill also tore the proxy's last packet.
        FileOutputStream(part(C1.TIER_PROXY), true).use { it.write(ByteArray(100) { 0x47 }) }

        val timebase = timebase()
        val resumed = C1.TIERS.associateWith { segmenter(it, timebase) }

        assertEquals(C1.TIERS, segments.map { it.tier })
        segments.forEach { assertRecoveredSecondSegment(it, it.tier) }
        assertTrue(gaps.isEmpty())
        val lines = storage.sidecar("s1").readLines().map { JSONObject(it) }
        assertEquals(listOf(0L, 0L, 1L, 1L), lines.map { it.getLong("seq") })
        assertEquals(segments[0].sha256, lines[2].getString("sha256"))

        // Recording goes on at seq 2.
        segments.clear()
        feed(resumed.values, 540, 550)
        resumed.values.forEach { it.finish() }
        assertEquals(listOf(2L, 2L), segments.map { it.seq })
    }

    @Test
    fun stopAfterCrashRecoversWithoutASegmenter() {
        crashMidSecondSegment()

        C1.TIERS.forEach { tier -> recovery(tier).recover(onSegment = { segments += it }, onGap = { gaps += it }) }

        assertEquals(C1.TIERS, segments.map { it.tier })
        segments.forEach { assertRecoveredSecondSegment(it, it.tier) }
        // A second run finds nothing left to do.
        C1.TIERS.forEach { tier -> recovery(tier).recover(onSegment = { segments += it }, onGap = { gaps += it }) }
        assertEquals(2, segments.size)
    }

    @Test
    fun corruptPacketEndsTheRecoveredSegment() {
        crashMidSecondSegment()
        val file = part(C1.TIER_PROXY)
        // Break the sync byte of the packet that starts the 21st frame's PES.
        val bytes = file.readBytes()
        val starts = videoPesStarts(bytes)
        RandomAccessFile(file, "rw").use { raf ->
            raf.seek(starts[20].toLong())
            raf.write(0x00)
        }

        recovery(C1.TIER_PROXY).recover(onSegment = { segments += it }, onGap = { gaps += it })

        // Frames 0..19 are whole; frame 20's first packet is gone.
        assertEquals(19, segments.single().frames)
    }

    @Test
    fun partialWithoutACompleteFrameIsAnnouncedAsAGap() {
        val timebase = timebase()
        val tiers = C1.TIERS.associateWith { segmenter(it, timebase) }
        feed(tiers.values, 0, 1)

        C1.TIERS.forEach { tier -> recovery(tier).recover(onSegment = { segments += it }, onGap = { gaps += it }) }

        assertTrue(segments.isEmpty())
        assertEquals(C1.TIERS, gaps.map { it.tier })
        gaps.forEach { gap ->
            assertEquals("s1", gap.sessionId)
            assertEquals(serverBaseMs, gap.fromServerMs)
            assertEquals(TsPartRecovery.REASON_NO_COMPLETE_FRAME, gap.reason)
        }
        C1.TIERS.forEach { tier ->
            assertTrue(storage.tierDir("s1", tier).list()!!.isEmpty())
            assertEquals(-1L, seqStore.lastSeq("s1", tier))
        }
        assertFalse(storage.sidecar("s1").exists())
    }

    @Test
    fun partialWithoutMetadataOrOutOfSequenceIsDropped() {
        seqStore.commitSeq("s1", C1.TIER_PROXY, 4)
        val dir = storage.tierDir("s1", C1.TIER_PROXY)
        dir.mkdirs()
        File(dir, "000005.ts.part").writeText("no metadata")
        File(dir, "000009.ts.part").writeText("not the next seq")
        File(dir, "000009.ts.part.json").writeText("""{"mediaStartServerMs":1}""")
        File(dir, "000007.ts.part.json").writeText("""{"mediaStartServerMs":1}""")

        recovery(C1.TIER_PROXY).recover(onSegment = { segments += it }, onGap = { gaps += it })

        assertTrue(dir.list()!!.isEmpty())
        assertTrue(segments.isEmpty())
        assertTrue(gaps.isEmpty())
        assertEquals(4L, seqStore.lastSeq("s1", C1.TIER_PROXY))
    }

    @Test
    fun gapEventCarriesTheLostTierAndStart() {
        val body = C1Events.recordingGap(SegmentGap("s1", C1.TIER_PROXY, 42L, "why"))

        assertEquals("s1", body.getString("sessionId"))
        assertEquals("proxy", body.getString("tier"))
        assertEquals(42L, body.getLong("fromServerMs"))
        assertEquals("why", body.getString("reason"))
        assertEquals("recording.gap", C1.RECORDING_GAP)
    }

    /** Byte offsets of the TS packets that start a video PES. */
    private fun videoPesStarts(bytes: ByteArray): List<Int> =
        (0 until bytes.size / MpegTsMuxer.PACKET_SIZE).map { it * MpegTsMuxer.PACKET_SIZE }.filter { offset ->
            val pid = ((bytes[offset + 1].toInt() and 0x1F) shl 8) or (bytes[offset + 2].toInt() and 0xFF)
            pid == MpegTsMuxer.VIDEO_PID && bytes[offset + 1].toInt() and 0x40 != 0
        }
}
