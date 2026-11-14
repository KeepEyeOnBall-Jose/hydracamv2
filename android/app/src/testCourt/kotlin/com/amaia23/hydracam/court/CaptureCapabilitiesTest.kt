package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureCapabilitiesTest {
    private val uhd = 3840 to 2160
    private val hd = 1920 to 1080
    private val proxy = 1280 to 720
    private val lens = LensInfo(
        cameraId = "0",
        viewWidth = 1.33,
        zoomRange = 1.0..8.0,
        aeFpsRanges = listOf(15..30, 30..30),
        videoSizes = listOf(uhd, hd, proxy),
        videoStabilizationModes = listOf(0, 1),
        oisModes = listOf(0, 1),
        manualSensor = true,
        exposureRangeNs = 10_000L..100_000_000L,
        isoRange = 50..3200,
    )

    private fun profiles(
        lens: LensInfo = this.lens,
        frames: Map<Pair<Int, Int>, Long> = mapOf(uhd to 33_333_333L, hd to 33_333_333L, proxy to 33_333_333L),
        encoder: (Pair<Int, Int>, Int) -> Int? = { _, _ -> 50_000 },
    ) = CaptureCapabilities.profiles(listOf(lens), { _, size -> frames[size] }, encoder)

    @Test
    fun advertises4k30OnlyWhenTheCameraAndBothEncodersSupportIt() {
        val modes = profiles()
        assertEquals(listOf("2160p", "1080p", "720p"), modes.map { it.masterRes })
        assertTrue(modes.all { it.fps == 30 && it.lens == "wide" && it.codec == "avc" })
        assertEquals(50_000, modes.first().maxMasterKbps)
    }

    @Test
    fun excludes4kWhenTheSensorCannotDeliverThirtyFramesAtThatSize() {
        val modes = profiles(frames = mapOf(uhd to 66_666_666L, hd to 33_333_333L, proxy to 33_333_333L))
        assertEquals(listOf("1080p", "720p"), modes.map { it.masterRes })
    }

    @Test
    fun unknownCameraTimingDoesNotPromise4k() {
        assertFalse(profiles(frames = mapOf(hd to 33_333_333L, proxy to 33_333_333L)).any { it.masterRes == "2160p" })
        assertTrue(profiles(frames = emptyMap()).isEmpty())
    }

    @Test
    fun unavailableProxyEncoderOrCameraOutputRefusesAllProfiles() {
        assertTrue(profiles(encoder = { size, _ -> if (size == proxy) null else 50_000 }).isEmpty())
        assertTrue(profiles(encoder = { _, _ -> 1_999 }).isEmpty())
        assertTrue(profiles(lens = lens.copy(videoSizes = listOf(uhd, hd))).isEmpty())
        assertTrue(profiles(frames = mapOf(uhd to 33_333_333L, proxy to 66_666_666L)).isEmpty())
    }

    @Test
    fun encoderRateAndBitrateCapabilitiesAreKeptPerResolution() {
        val modes = profiles(encoder = { size, fps ->
            assertEquals(30, fps)
            when (size) {
                uhd -> null
                else -> 20_000
            }
        })
        assertEquals(listOf("1080p", "720p"), modes.map { it.masterRes })
        assertTrue(modes.all { it.maxMasterKbps == 20_000 })
    }

    @Test
    fun profileIsAnAdditiveHelloCapabilityWithConcreteSettings() {
        val profile = profiles().first()
        val caps = CourtCaps("2160p", listOf(30), false, 3, true, true, listOf(profile)).toJson()
        val json = caps.getJSONArray("captureProfiles").getJSONObject(0)
        assertEquals("2160p", json.getString("masterRes"))
        assertEquals(30, json.getInt("fps"))
        assertEquals("wide", json.getString("lens"))
        assertEquals("avc", json.getString("codec"))
        assertEquals(50_000, json.getInt("maxMasterKbps"))
    }

    @Test
    fun anotherLensDoesNotInheritTheWideCameras4kCapability() {
        val ultrawide = lens.copy(cameraId = "2", viewWidth = 2.8, videoSizes = listOf(hd, proxy))
        val modes = CaptureCapabilities.profiles(
            listOf(lens, ultrawide),
            { _, _ -> 33_333_333L },
            { _, _ -> 50_000 },
        )
        assertTrue(modes.any { it.lens == "wide" && it.masterRes == "2160p" })
        assertEquals(listOf("1080p", "720p"), modes.filter { it.lens == "ultrawide" }.map { it.masterRes })
    }

    @Test
    fun thirtyFpsRequiresBothCameraTimingAndAnAeRange() {
        assertTrue(profiles(lens = lens.copy(aeFpsRanges = listOf(15..15))).isEmpty())
        assertFalse(profiles(frames = mapOf(uhd to 0L, proxy to 33_333_333L)).any { it.masterRes == "2160p" })
    }

    @Test
    fun integerNanosecondRoundingDoesNotExcludeThirtyOrSixtyFps() {
        val modes = profiles(frames = mapOf(uhd to 33_333_334L, hd to 33_333_334L, proxy to 33_333_334L))
        assertEquals(3, modes.size)
        val faster = profiles(
            lens = lens.copy(aeFpsRanges = listOf(30..30, 60..60)),
            frames = mapOf(uhd to 33_333_334L, hd to 16_666_667L, proxy to 16_666_667L),
        )
        assertEquals(listOf("1080p", "720p"), faster.filter { it.fps == 60 }.map { it.masterRes })
        assertEquals(3, faster.count { it.fps == 30 })
    }

    @Test
    fun sixtyFpsRequiresTheEncoderAsWellAsTheCamera() {
        val modes = profiles(
            lens = lens.copy(aeFpsRanges = listOf(30..30, 60..60)),
            frames = mapOf(uhd to 16_666_667L, hd to 16_666_667L, proxy to 16_666_667L),
            encoder = { _, fps -> if (fps == 60) null else 50_000 },
        )
        assertEquals(3, modes.size)
        assertTrue(modes.all { it.fps == 30 })
    }
}
