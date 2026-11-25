package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

    private fun segmenter(
        hasAudio: Boolean = false,
        estimate: ClockEstimate? = ClockEstimate(1_000, 12),
        videoCodec: TsVideoCodec = TsVideoCodec.H264,
    ) = TsSegmenter(
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
        clock = FakePhoneClock(),
        videoCodec = videoCodec,
    )

    private fun feed(target: TsSegmenter, from: Int, until: Int) {
        for (index in from until until) {
            target.onVideoFrame(
                index * frameUs,
                ByteArray(200) { index.toByte() },
                isKeyframe = index % 30 == 0 && index > 0,
            )
        }
    }

    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toHex()

    @Test
    fun cutsOnIdrWritesSidecarAndSupportsAudioAndAbort() {
        val target = segmenter(hasAudio = true)
        target.onVideoConfig(byteArrayOf(0, 0, 0, 1, 0x67))
        target.onAudioFrame(0, ByteArray(100))
        feed(target, 0, 400)
        target.onAudioFrame(30 * frameUs + 1_000, ByteArray(100))

        assertEquals(listOf(0L, 1L), segments.map { it.seq })
        assertEquals(180, segments[0].frames)
        assertEquals(5_999L, segments[0].durationMs)
        assertEquals(serverBaseMs + 30 * frameUs / 1_000, segments[0].mediaStartServerMs)
        assertEquals(2, syncRequests)

        assertEquals(2L, target.finish())
        assertEquals(2L, target.finish())
        assertEquals(3, segments.size)
        assertEquals(2L, seqStore.lastSeq("s1", C1.TIER_PROXY))
        segments.forEach { record ->
            assertEquals(sha256(record.file), record.sha256)
            assertEquals(0L, record.bytes % MpegTsMuxer.PACKET_SIZE)
        }

        val logger = RecordingPhoneLogger()
        val recovered = SegmentSidecarReader(storage, logger).readAll()
        assertEquals(3, recovered.size)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun hevcSegmentsDeclareTheHevcStreamType() {
        val target = segmenter(videoCodec = TsVideoCodec.HEVC)
        target.onVideoConfig(byteArrayOf(0, 0, 0, 1, 0x40, 1))
        feed(target, 0, 40)
        target.finish()

        val bytes = segments.single().file.readBytes()
        val pmt = bytes.copyOfRange(MpegTsMuxer.PACKET_SIZE, 2 * MpegTsMuxer.PACKET_SIZE)
        assertEquals(MpegTsMuxer.STREAM_TYPE_HEVC, pmt[5 + 12].toInt() and 0xFF)
    }

    @Test
    fun openSegmentAbortAndFailureLeaveSeqUncommitted() {
        val abortTarget = segmenter()
        feed(abortTarget, 30, 40)
        val dir = storage.tierDir("s1", C1.TIER_PROXY)
        assertEquals(listOf("000000.ts.part", "000000.ts.part.json"), dir.list()!!.sorted())
        abortTarget.abort()
        assertTrue(dir.list()!!.isEmpty())
        assertEquals(-1L, seqStore.lastSeq("s1", C1.TIER_PROXY))

        File(dir, "000000.ts").apply {
            mkdirs()
            File(this, "occupied").writeText("x")
        }
        val failingTarget = segmenter(estimate = null)
        feed(failingTarget, 30, 40)
        assertThrows(IOException::class.java) { failingTarget.finish() }
        assertEquals(-1L, seqStore.lastSeq("s1", C1.TIER_PROXY))
    }

    @Test
    fun sidecarReaderJsonlAppenderTimebaseAndPtsClockWorkOnJvm() {
        val logger = RecordingPhoneLogger()
        val reader = SegmentSidecarReader(storage, logger)
        assertTrue(reader.readAll().isEmpty())
        assertNotNull(storage.signalsLog().parentFile)

        assertThrows(IllegalArgumentException::class.java) { storage.sessionDir("../bad") }

        val record = SegmentRecord(
            sessionId = "s1",
            slot = "A",
            tier = C1.TIER_PROXY,
            seq = 0,
            file = File(storage.tierDir("s1", C1.TIER_PROXY), "000000.ts"),
            bytes = 188,
            sha256 = "ab".repeat(32),
            mediaStartServerMs = serverBaseMs,
            durationMs = 6_000,
            frames = 180,
            offsetMs = 0,
            rttMs = 10,
        )
        val sidecar = JsonlAppender(storage.sidecar("s1"))
        sidecar.append(record.toSidecarJson(1L))
        storage.sidecar("s1").appendText("""{"broken":""")
        val second = record.copy(seq = 1, file = File(storage.tierDir("s1", C1.TIER_PROXY), "000001.ts"))
        sidecar.append(second.toSidecarJson(2L))

        val read = reader.readAll()
        assertEquals(listOf(0L, 1L), read.map { it.seq })
        assertEquals(1, logger.warnings.size)
        assertNull(reader.parse(storage.sessionDir("s1"), "{bad"))

        var skew = 0L
        val timebase = SessionTimebase { ptsUs -> serverBaseMs + ptsUs / 1_000 + skew }
        assertEquals(serverBaseMs + 100L, timebase.serverMs(100_000L))
        timebase.anchor(100_000L)
        skew = 999L
        assertEquals(serverBaseMs + 150L, timebase.serverMs(150_000L))
        assertEquals(MpegTsMuxer.usTo90k(50_000L), timebase.relative90k(150_000L))

        val realtimeUs = 50_000_000L
        val monotonicUs = 900_000_000L
        val ptsClock = PtsClock(
            useRealtime = true,
            realtimeUs = { realtimeUs },
            monotonicUs = { monotonicUs },
            wallMs = { serverBaseMs },
        )
        assertTrue(ptsClock.check(monotonicUs - 30_000))
        assertEquals(monotonicUs, ptsClock.nowUs())
        assertFalse(ptsClock.check(realtimeUs))
        assertEquals(serverBaseMs - 250L, ptsClock.wallMsFor(monotonicUs - 250_000))
        assertEquals("00ff", byteArrayOf(0x00, 0xFF.toByte()).toHex())
    }
}
