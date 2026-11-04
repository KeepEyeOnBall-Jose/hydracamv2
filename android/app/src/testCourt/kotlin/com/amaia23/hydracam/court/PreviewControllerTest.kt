package com.amaia23.hydracam.court

import android.util.Size
import android.view.Surface
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** H8/S1 live preview: C1 `preview.start`/`preview.stop` drive one publisher behind the seam. */
class PreviewControllerTest {
    private val clock = FakeClock(now = 0)
    private val camera = FakeSeam()
    private val encoder = FakeEncoder()
    private val transport = FakeTransport()
    private val logger = RecordingLogger()
    private val identity = PreviewIdentity("club-7", "left")
    private val config = PreviewCodecConfig(byteArrayOf(0, 0, 0, 1, 0x67), byteArrayOf(0, 0, 0, 1, 0x68))
    private val controller = PreviewController(camera, encoder, transport, clock, logger)

    private fun command(
        token: String = "jwt-1",
        kbps: Int = 1_000,
        ttlS: Long = 300,
        url: String = "srt://relay:8890",
    ) = PreviewStart.fromJson(
        JSONObject()
            .put("publishUrl", url)
            .put("token", token)
            .put("width", 640)
            .put("height", 360)
            .put("fps", 20)
            .put("kbps", kbps)
            .put("ttlS", ttlS),
    )

    private fun frame(key: Boolean = false, size: Int = 1_000) = PreviewFrame(ByteArray(size), clock.now * 1_000, key)

    private fun publishing(start: PreviewStart = command()): PreviewController {
        assertEquals(CommandResult.Ack, controller.start(start, identity))
        controller.onCodecConfig(config)
        transport.listener!!.onConnected()
        return controller
    }

    @Test
    fun startHoldsTheCameraAndWaitsForTheCodecConfigBeforeConnecting() {
        assertEquals(CommandResult.Ack, controller.start(command(), identity))

        assertTrue(camera.held)
        assertEquals(20, camera.fps)
        assertTrue(encoder.bitrates.last() in 800..900)
        assertTrue(transport.connects.isEmpty())
        assertTrue(controller.isActive)
        assertEquals("waiting", controller.stateName)

        controller.onCodecConfig(config)
        assertEquals(listOf("srt://relay:8890?streamid=publish:court/club-7/left:device:jwt-1"), transport.connects)
        assertEquals(config, transport.config)
        assertEquals("connecting", controller.stateName)
    }

    @Test
    fun aKnownCodecConfigConnectsAtOnce() {
        controller.onCodecConfig(config)
        controller.start(command(), identity)

        assertEquals(1, transport.connects.size)
    }

    @Test
    fun noEncoderOrNoEnrollmentIsRefusedWithoutTouchingTheCamera() {
        val unsupported = PreviewController(camera, null, transport, clock, logger)

        assertEquals(C1NackCode.UNSUPPORTED, (unsupported.start(command(), identity) as CommandResult.Nack).code)
        assertEquals(C1NackCode.NOT_ENROLLED, (controller.start(command(), null) as CommandResult.Nack).code)
        assertFalse(camera.held)
        assertEquals(0, camera.fpsCalls)
        assertFalse(controller.isActive)
    }

    @Test
    fun theStreamStartsWithAKeyFrame() {
        publishing()
        assertEquals(1, encoder.keyFrameRequests)
        assertEquals("publishing", controller.stateName)

        controller.onFrame(frame())
        controller.onFrame(frame())
        assertTrue(transport.sent.isEmpty())

        controller.onFrame(frame(key = true))
        controller.onFrame(frame())
        assertEquals(listOf(true, false), transport.sent.map { it.keyFrame })
        assertEquals(2, controller.stats()["framesSent"])
        assertEquals(2, controller.stats()["framesDropped"])
    }

    @Test
    fun framesBeforeTheConnectionAreNotSent() {
        controller.onFrame(frame(key = true))
        controller.start(command(), identity)
        controller.onCodecConfig(config)
        controller.onFrame(frame(key = true))

        assertTrue(transport.sent.isEmpty())
    }

    @Test
    fun reArmingTheSameTargetKeepsTheConnectionAndExtendsTheTtl() {
        publishing()
        controller.onFrame(frame(key = true))
        clock.now = 250_000

        assertEquals(CommandResult.Ack, controller.start(command(token = "jwt-2", kbps = 600), identity))
        assertEquals(1, transport.connects.size)
        assertEquals(0, transport.disconnects)
        assertEquals(2, encoder.keyFrameRequests)
        assertTrue(encoder.bitrates.last() <= 600)

        clock.now = 400_000
        controller.tick()
        assertTrue("the second start moved the TTL to 550 s", controller.isActive)

        // The next reconnect uses the fresh token.
        transport.listener!!.onFailed("relay closed")
        clock.now += 1_000
        controller.tick()
        assertEquals("srt://relay:8890?streamid=publish:court/club-7/left:device:jwt-2", transport.connects.last())
    }

    @Test
    fun aNewTargetReconnects() {
        publishing()

        controller.start(command(url = "srt://other-relay:8890"), identity)

        assertEquals(1, transport.disconnects)
        assertEquals(2, transport.connects.size)
        assertTrue(transport.connects.last().startsWith("srt://other-relay:8890?"))
        assertEquals("connecting", controller.stateName)
    }

    @Test
    fun ttlExpiryStopsLikePreviewStop() {
        publishing()
        clock.now = 299_999
        controller.tick()
        assertTrue(controller.isActive)

        clock.now = 300_000
        controller.tick()

        assertFalse(controller.isActive)
        assertEquals(1, transport.disconnects)
        assertEquals(0, camera.fps)
        assertFalse(camera.held)
        assertEquals(0, controller.measuredKbps())
        assertTrue(logger.infos.any { it.contains("ttl") })
    }

    @Test
    fun stopIsIdempotent() {
        controller.stop("preview.stop")
        assertEquals(0, transport.disconnects)
        assertEquals(0, camera.fpsCalls)

        publishing()
        controller.stop("preview.stop")
        controller.stop("preview.stop")
        assertEquals(1, transport.disconnects)
        assertEquals("off", controller.stateName)
    }

    @Test
    fun failuresBackOffAndFallBackToRtmps() {
        publishing()
        val srt = transport.connects.single()

        transport.listener!!.onFailed("timeout")
        assertEquals("backoff", controller.stateName)
        clock.now += 999
        controller.tick()
        assertEquals(1, transport.connects.size)
        clock.now += 1
        controller.tick()
        assertEquals(listOf(srt, srt), transport.connects)

        transport.listener!!.onFailed("timeout")
        clock.now += 2_000
        controller.tick()
        assertEquals("rtmps://relay:1936/court/club-7/left?token=jwt-1", transport.connects.last())

        transport.listener!!.onConnected()
        assertEquals("publishing", controller.stateName)
        assertEquals(1, controller.stats()["urlIndex"])
    }

    @Test
    fun backoffIsCapped() {
        publishing()
        repeat(10) {
            transport.listener!!.onFailed("down")
            clock.now += PreviewTuning().maxBackoffMs
            controller.tick()
        }

        assertEquals(11, transport.connects.size)
    }

    @Test
    fun eventsFromAnOldConnectionAreIgnored() {
        publishing()
        val old = transport.listener!!
        controller.start(command(url = "srt://other-relay:8890"), identity)

        old.onFailed("late")
        old.onConnected()

        assertEquals("connecting", controller.stateName)
        assertEquals(2, transport.connects.size)
    }

    @Test
    fun aDroppedConnectionWhilePublishingReconnects() {
        publishing()
        controller.onFrame(frame(key = true))

        transport.listener!!.onFailed("Shutdown received from server")
        clock.now += 1_000
        controller.tick()
        transport.listener!!.onConnected()

        controller.onFrame(frame())
        assertEquals(1, transport.sent.size)
        assertEquals(2, encoder.keyFrameRequests)
    }

    @Test
    fun overBudgetFramesAreDroppedUntilTheNextKeyFrame() {
        controller.start(command(kbps = 100), identity)
        controller.onCodecConfig(config)
        transport.listener!!.onConnected()

        // 100 kbps allows 12.5 kB of burst; 8 kB frames fit once.
        controller.onFrame(frame(key = true, size = 8_000))
        controller.onFrame(frame(size = 8_000))
        clock.now += 100
        controller.onFrame(frame(size = 1_000))
        clock.now += 1_000
        controller.onFrame(frame(size = 1_000))
        controller.onFrame(frame(key = true, size = 1_000))

        assertEquals(listOf(true, true), transport.sent.map { it.keyFrame })
        assertTrue("keyframe requested again", encoder.keyFrameRequests >= 2)
    }

    @Test
    fun keyFrameRequestsAreRateLimited() {
        controller.start(command(kbps = 100), identity)
        controller.onCodecConfig(config)
        transport.listener!!.onConnected()
        controller.onFrame(frame(key = true, size = 12_000))
        repeat(20) { controller.onFrame(frame(key = true, size = 12_000)) }

        assertEquals(2, encoder.keyFrameRequests)
    }

    @Test
    fun theGovernorDrivesEncoderBitrateAndCameraFps() {
        publishing()
        val first = encoder.bitrates.last()
        repeat(200) {
            clock.now += 50
            controller.onFrame(frame(key = true, size = 7_000))
            if (clock.now % 500 == 0L) controller.tick()
        }

        assertTrue(encoder.bitrates.last() < first)
        assertTrue(controller.measuredKbps() in 1..1_000)
        assertEquals(controller.stats()["fps"], camera.fps)
    }

    @Test
    fun codecConfigChangesAreLoggedAndKept() {
        publishing()
        val next = PreviewCodecConfig(byteArrayOf(1), byteArrayOf(2))
        controller.onCodecConfig(next)

        assertEquals(1, transport.connects.size)
        transport.listener!!.onFailed("x")
        clock.now += 1_000
        controller.tick()
        assertEquals(next, transport.config)
    }

    @Test
    fun aKeyFrameBiggerThanTheBucketIsStillSentAtALowCap() {
        controller.start(command(kbps = 200), identity)
        controller.onCodecConfig(config)
        transport.listener!!.onConnected()

        // 200 kbps is a 25 kB bucket; the stream must still start with a 40 kB key frame.
        controller.onFrame(frame(key = true, size = 40_000))
        clock.now += 50
        controller.onFrame(frame(size = 1_000))
        clock.now += 2_000
        controller.onFrame(frame(key = true, size = 40_000))

        assertEquals(listOf(40_000, 40_000), transport.sent.map { it.data.size })
        assertEquals(listOf(true, true), transport.sent.map { it.keyFrame })
    }

    @Test
    fun theLargestTtlNeverExpiresEarly() {
        clock.now = 1_700_000_000_000L
        publishing(command(ttlS = Long.MAX_VALUE / 1_000))

        clock.now += 1_000
        controller.tick()

        assertTrue(controller.isActive)
        assertEquals("publishing", controller.stateName)
    }

    @Test
    fun aCameraThatFailsToOpenIsRetriedAndReportedUntilItOpens() {
        camera.opens = false
        publishing()
        assertTrue(controller.isPreviewing)
        assertNull(controller.problem)

        // Still within the grace period: the open is async.
        clock.now = 4_999
        controller.tick()
        assertEquals(1, camera.holds)
        assertEquals("opening", controller.stats()["camera"])

        clock.now = 5_000
        controller.tick()
        assertEquals(2, camera.holds)
        assertFalse(controller.isPreviewing)
        assertEquals("preview_camera_closed", controller.problem)
        assertEquals("failed", controller.stats()["camera"])
        assertEquals(1, logger.warnings.count { it.contains("did not open") })

        clock.now = 10_000
        controller.tick()
        assertEquals(3, camera.holds)
        assertEquals(2, controller.stats()["cameraRetries"])
        assertEquals(1, logger.warnings.count { it.contains("did not open") })

        camera.opens = true
        val keyFrames = encoder.keyFrameRequests
        clock.now = 10_500
        controller.tick()
        assertTrue(controller.isPreviewing)
        assertNull(controller.problem)
        assertEquals("open", controller.stats()["camera"])
        assertEquals(keyFrames + 1, encoder.keyFrameRequests)
        assertEquals(0, controller.stats()["cameraRetries"])

        controller.stop("preview.stop")
        assertFalse(controller.isPreviewing)
        assertNull(controller.problem)
        assertEquals("off", controller.stats()["camera"])
    }

    @Test
    fun aCameraThatStaysOpenIsNeverAskedForAgain() {
        publishing()
        repeat(40) {
            clock.now += 500
            controller.tick()
        }

        assertEquals(1, camera.holds)
        assertTrue(controller.isPreviewing)
    }

    @Test
    fun aReArmReopensAClosedCamera() {
        publishing()
        camera.opens = false

        controller.start(command(token = "jwt-2"), identity)
        assertEquals(2, camera.holds)
        controller.start(command(url = "srt://other-relay:8890"), identity)
        assertEquals(3, camera.holds)

        camera.opens = true
        controller.start(command(token = "jwt-3", url = "srt://other-relay:8890"), identity)
        assertEquals(3, camera.holds)
    }

    @Test
    fun statsNeverHoldCredentials() {
        publishing()
        val stats = controller.stats().toString()

        assertFalse(stats, stats.contains("jwt-1"))
        assertTrue(stats, stats.contains("relay"))
        assertNull(PreviewController(camera, encoder, transport, clock).stats()["target"])
    }

    private class FakeSeam : CourtPreviewSeam {
        var fps = 0
        var fpsCalls = 0
        var held = false
        var holds = 0

        /** Whether a hold opens the camera (false: the open fails, as on a busy camera). */
        var opens = true

        override fun previewOutputSizes(): List<Size> = emptyList()

        override fun setPreviewSurface(surface: Surface?) = Unit

        override fun setPreviewFps(fps: Int) {
            this.fps = fps
            fpsCalls++
        }

        override fun holdCameraForPreview(hold: Boolean) {
            held = hold
            if (hold) holds++
        }

        override fun cameraOpen(): Boolean = held && opens

        override fun captureWallMs(sensorNs: Long): Long = sensorNs / 1_000_000
    }

    private class FakeEncoder : PreviewEncoderControl {
        var keyFrameRequests = 0
        val bitrates = mutableListOf<Int>()

        override fun requestKeyFrame() {
            keyFrameRequests++
        }

        override fun setBitrateKbps(kbps: Int) {
            bitrates += kbps
        }
    }

    private class FakeTransport : PreviewTransport {
        val connects = mutableListOf<String>()
        val sent = mutableListOf<PreviewFrame>()
        var disconnects = 0
        var listener: PreviewTransport.Listener? = null
        var config: PreviewCodecConfig? = null

        override fun connect(url: String, config: PreviewCodecConfig, listener: PreviewTransport.Listener) {
            connects += url
            this.config = config
            this.listener = listener
        }

        override fun send(frame: PreviewFrame) {
            sent += frame
        }

        override fun disconnect() {
            disconnects++
        }
    }
}
