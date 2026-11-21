package com.amaia23.hydracam.phonecore

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
        clock = FakePhoneClock(),
    )

    private fun timebase() = SessionTimebase { ptsUs -> serverBaseMs + ptsUs / 1_000 }

    private fun recovery(tier: String) = TsPartRecovery(
        sessionId = "s1",
        slot = "A",
        tier = tier,
        directory = storage.tierDir("s1", tier),
        sidecar = JsonlAppender(storage.sidecar("s1")),
        seqStore = seqStore,
        clock = FakePhoneClock(),
    )

    private fun feed(targets: Collection<TsSegmenter>, from: Int, until: Int) {
        for (index in from until until) {
            targets.forEach { it.onVideoFrame(index * frameUs, ByteArray(200) { index.toByte() }, index % 180 == 0) }
        }
    }

    private fun crashMidSecondSegment() {
        val tb = timebase()
        val tiers = C1.TIERS.associateWith { segmenter(it, tb) }
        feed(tiers.values, 0, 225)
        assertEquals(2, segments.size)
        segments.clear()
    }

    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toHex()

    @Test
    fun recoversPartialSegmentAndStripsTrailingTornBytes() {
        crashMidSecondSegment()
        val proxyPart = File(storage.tierDir("s1", C1.TIER_PROXY), "000001.ts.part")
        FileOutputStream(proxyPart, true).use { it.write(ByteArray(100) { 0x47 }) }

        C1.TIERS.forEach { tier -> recovery(tier).recover(onSegment = { segments += it }, onGap = { gaps += it }) }

        assertEquals(C1.TIERS, segments.map { it.tier })
        segments.forEach { record ->
            assertEquals(1L, record.seq)
            assertEquals(44, record.frames)
            assertEquals(0L, record.bytes % MpegTsMuxer.PACKET_SIZE)
            assertEquals(sha256(record.file), record.sha256)
        }
        assertTrue(gaps.isEmpty())
    }

    @Test
    fun corruptPacketSingleFrameGapAndBadPartCleanupBehaveSafely() {
        crashMidSecondSegment()
        val proxyPart = File(storage.tierDir("s1", C1.TIER_PROXY), "000001.ts.part")
        val bytes = proxyPart.readBytes()
        val starts = (0 until bytes.size / MpegTsMuxer.PACKET_SIZE)
            .map { it * MpegTsMuxer.PACKET_SIZE }
            .filter { offset ->
                val pid = ((bytes[offset + 1].toInt() and 0x1F) shl 8) or (bytes[offset + 2].toInt() and 0xFF)
                pid == MpegTsMuxer.VIDEO_PID && bytes[offset + 1].toInt() and 0x40 != 0
            }
        RandomAccessFile(proxyPart, "rw").use { raf ->
            raf.seek(starts[20].toLong())
            raf.write(0x00)
        }
        recovery(C1.TIER_PROXY).recover(onSegment = { segments += it }, onGap = { gaps += it })
        assertEquals(19, segments.single().frames)

        segments.clear()
        val gapStorage = CourtStorage(temp.newFolder("gap-court"))
        val gapSeqs = InMemorySegmentSeqStore()
        val gapSeg = TsSegmenter(
            sessionId = "s2",
            slot = "A",
            tier = C1.TIER_PROXY,
            directory = gapStorage.tierDir("s2", C1.TIER_PROXY),
            sidecar = JsonlAppender(gapStorage.sidecar("s2")),
            seqStore = gapSeqs,
            timebase = timebase(),
            segmentDurationUs = 6_000_000,
            frameDurationUs = frameUs,
            hasAudio = false,
            clockEstimate = { null },
            onSegment = { segments += it },
            onGap = { gaps += it },
        )
        gapSeg.onVideoFrame(0, ByteArray(100), isKeyframe = true)
        TsPartRecovery(
            sessionId = "s2",
            slot = "A",
            tier = C1.TIER_PROXY,
            directory = gapStorage.tierDir("s2", C1.TIER_PROXY),
            sidecar = JsonlAppender(gapStorage.sidecar("s2")),
            seqStore = gapSeqs,
        ).recover(onSegment = { segments += it }, onGap = { gaps += it })

        assertTrue(segments.isEmpty())
        assertEquals(TsPartRecovery.REASON_NO_COMPLETE_FRAME, gaps.single().reason)
        assertFalse(gapStorage.sidecar("s2").exists())

        val dir = storage.tierDir("s1", C1.TIER_MASTER)
        File(dir, "000001.ts.part").delete()
        File(dir, "000001.ts.part.json").delete()
        File(dir, "000009.ts.part").writeText("wrong seq")
        File(dir, "000009.ts.part.json").writeText("""{"mediaStartServerMs":1}""")
        File(dir, "orphan.ts.part.json").writeText("""{"mediaStartServerMs":1}""")
        recovery(C1.TIER_MASTER).recover(onSegment = { segments += it }, onGap = { gaps += it })
        assertFalse(File(dir, "000009.ts.part").exists())
        assertFalse(File(dir, "orphan.ts.part.json").exists())
    }
}
