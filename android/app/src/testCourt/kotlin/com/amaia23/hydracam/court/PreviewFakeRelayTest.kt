package com.amaia23.hydracam.court

import android.util.Size
import android.view.Surface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * H8/S1 end to end over a real socket: [PreviewController] + the real RootEncoder RTMP client
 * ([RootEncoderPreviewTransport]) publish to [FakeRtmpRelay], all on one preview executor.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PreviewFakeRelayTest {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Executors.newSingleThreadExecutor()
    private val logger = RecordingLogger()
    private val camera = Seam()
    private val encoder = Encoder()
    private val transport = RootEncoderPreviewTransport(post = executor::execute, logger = logger)
    private val controller = PreviewController(camera, encoder, transport, CourtClock.SYSTEM, logger)
    private val identity = PreviewIdentity("club-7", "left")
    private val sps = byteArrayOf(0x67, 0x42, 0xC0.toByte(), 0x1E, 0xDA.toByte(), 0x02, 0x80.toByte(), 0xBF.toByte())
    private val pps = byteArrayOf(0x68, 0xCE.toByte(), 0x3C, 0x80.toByte())
    private val config = PreviewCodecConfig(START + sps, START + pps)
    private var relay: FakeRtmpRelay? = null

    @Before
    fun setUp() {
        // On a phone RootEncoder's callbacks hop through the main looper; here a plain thread.
        Dispatchers.setMain(main.asCoroutineDispatcher())
    }

    @After
    fun tearDown() {
        onPreview { controller.stop("test end") }
        relay?.close()
        executor.shutdown()
        executor.awaitTermination(5, TimeUnit.SECONDS)
        Dispatchers.resetMain()
        main.shutdownNow()
    }

    private fun <T> onPreview(block: () -> T): T = executor.submit(block).get(5, TimeUnit.SECONDS)

    private fun start(url: String): CommandResult = onPreview {
        val body = JSONObject()
            .put("publishUrl", url)
            .put("token", TOKEN)
            .put("width", 640)
            .put("height", 360)
            .put("fps", 20)
            .put("kbps", 1_000)
            .put("ttlS", 300)
        controller.start(PreviewStart.fromJson(body), identity)
    }

    private fun awaitState(name: String): Boolean = FakeRtmpRelay.poll(FakeRtmpRelay.TIMEOUT_MS) {
        onPreview {
            controller.stateName
        } == name
    }

    private fun frame(i: Int, key: Boolean, baseUs: Long = 0): PreviewFrame {
        val nal = if (key) {
            byteArrayOf(
                0x65,
                0x88.toByte(),
                0x84.toByte(),
                i.toByte(),
            )
        } else {
            byteArrayOf(0x41, 0x9A.toByte(), i.toByte())
        }
        return PreviewFrame(START + nal + ByteArray(200) { i.toByte() }, baseUs + i * FRAME_US, key)
    }

    @Test
    fun publishesToTheRelayPathWithTheTokenAndStartsWithTheSequenceHeaderAndAKeyFrame() {
        val relay = FakeRtmpRelay().also { relay = it }

        assertEquals(CommandResult.Ack, start("rtmp://127.0.0.1:${relay.port}"))
        onPreview { controller.onCodecConfig(config) }
        assertTrue("publishing", awaitState("publishing"))
        assertTrue(camera.held)
        assertEquals(1, encoder.keyFrames)

        onPreview {
            controller.onFrame(frame(0, key = false)) // before the key frame: dropped
            for (i in 1..5) controller.onFrame(frame(i, key = i == 1))
        }
        assertTrue("video arrived", relay.awaitVideo(5))

        assertTrue("token reaches the relay", "${relay.tcUrl} ${relay.streamName}".contains("token=$TOKEN"))
        assertTrue("court/club-7/left", "${relay.tcUrl}/${relay.streamName}".contains("court/club-7/left"))
        assertEquals(
            listOf("connect", "createStream", "publish"),
            relay.commands.filter {
                it in
                    setOf("connect", "createStream", "publish")
            },
        )

        val header = relay.video.first()
        assertEquals("AVC key frame tag", 0x17, header[0].toInt())
        assertEquals("sequence header", 0, header[1].toInt())
        assertTrue("SPS in the AVC config", contains(header, sps))
        assertTrue("PPS in the AVC config", contains(header, pps))

        val firstFrame = relay.video[1]
        assertEquals("first coded frame is a key frame", 0x17, firstFrame[0].toInt())
        assertEquals("NALU packet", 1, firstFrame[1].toInt())
        assertEquals("then inter frames", 0x27, relay.video[2][0].toInt())
        assertEquals(5, onPreview { controller.stats()["framesSent"] })

        onPreview { controller.stop("preview.stop") }
        assertTrue("stop disconnects", relay.awaitClosed())
        assertFalse(camera.held)
        assertEquals(0, camera.fps)
        assertFalse("no token in logs", (logger.infos + logger.warnings).any { it.contains(TOKEN) })
    }

    @Test
    fun sensorBootTimestampsAreRebasedToZeroOnTheWire() {
        val relay = FakeRtmpRelay().also { relay = it }

        start("rtmp://127.0.0.1:${relay.port}")
        onPreview { controller.onCodecConfig(config) }
        assertTrue("publishing", awaitState("publishing"))
        // Encoder pts are sensor boot time: 30 days of uptime overflows RTMP's signed 32-bit ms.
        onPreview { for (i in 0..4) controller.onFrame(frame(i, key = i == 0, baseUs = THIRTY_DAYS_US)) }
        assertTrue("video arrived", relay.awaitVideo(6))

        assertEquals(listOf(0L, 50L, 100L, 150L, 200L), relay.videoTimestamps.drop(1))
    }

    @Test
    fun aRefusedPublishBacksOff() {
        val relay = FakeRtmpRelay(publishCode = "NetStream.Publish.BadName").also { relay = it }

        start("rtmp://127.0.0.1:${relay.port}")
        onPreview { controller.onCodecConfig(config) }

        assertTrue("backoff", awaitState("backoff"))
        assertTrue(logger.warnings.any { it.contains("Preview publish failed") })
    }

    @Test
    fun anUnreachableRelayBacksOff() {
        val port = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { it.localPort }

        start("rtmp://127.0.0.1:$port")
        onPreview { controller.onCodecConfig(config) }

        assertTrue("backoff", awaitState("backoff"))
    }

    @Test
    fun anSrtTargetUsesTheSrtClientAndStopsCleanly() {
        val port = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { it.localPort }

        assertEquals(CommandResult.Ack, start("srt://127.0.0.1:$port"))
        onPreview { controller.onCodecConfig(config) }
        assertEquals("connecting", onPreview { controller.stateName })
        assertTrue(logger.infos.any { it.contains("srt://127.0.0.1:$port?…") })

        onPreview { controller.stop("preview.stop") }
        assertEquals("off", onPreview { controller.stateName })
        assertFalse((logger.infos + logger.warnings).any { it.contains(TOKEN) })
    }

    private fun contains(haystack: ByteArray, needle: ByteArray): Boolean =
        (0..haystack.size - needle.size).any { i -> needle.indices.all { haystack[i + it] == needle[it] } }

    private class Seam : CourtPreviewSeam {
        @Volatile var held = false

        @Volatile var fps = 0

        override fun previewOutputSizes(): List<Size> = emptyList()

        override fun setPreviewSurface(surface: Surface?) = Unit

        override fun setPreviewFps(fps: Int) {
            this.fps = fps
        }

        override fun holdCameraForPreview(hold: Boolean) {
            held = hold
        }

        override fun cameraOpen(): Boolean = held

        override fun captureWallMs(sensorNs: Long): Long = sensorNs / 1_000_000
    }

    private class Encoder : PreviewEncoderControl {
        @Volatile var keyFrames = 0

        override fun requestKeyFrame() {
            keyFrames++
        }

        override fun setBitrateKbps(kbps: Int) = Unit
    }

    private companion object {
        const val TOKEN = "jwt-fake-relay-token-pad"
        const val FRAME_US = 50_000L
        const val THIRTY_DAYS_US = 30L * 24 * 3_600 * 1_000_000
        val START = byteArrayOf(0, 0, 0, 1)
    }
}
