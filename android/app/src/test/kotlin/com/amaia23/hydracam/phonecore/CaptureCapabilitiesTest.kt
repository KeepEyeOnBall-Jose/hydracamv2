package com.amaia23.hydracam.phonecore

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
    fun advertisesSupportedProfilesAndSerializesToJson() {
        val modes = profiles()
        assertEquals(listOf("2160p", "1080p", "720p"), modes.map { it.masterRes })
        assertTrue(modes.all { it.fps == 30 && it.lens == "wide" && it.codec == "avc" })
        val json = modes.first().toJson()
        assertEquals("2160p", json.getString("masterRes"))
        assertEquals(50_000, json.getInt("maxMasterKbps"))
    }

    @Test
    fun excludesModesWhenCameraTimingOrEncoderFallsShort() {
        val no4k = profiles(frames = mapOf(uhd to 66_666_666L, hd to 33_333_333L, proxy to 33_333_333L))
        assertEquals(listOf("1080p", "720p"), no4k.map { it.masterRes })
        assertFalse(profiles(frames = mapOf(hd to 33_333_333L, proxy to 33_333_333L)).any { it.masterRes == "2160p" })
        assertTrue(profiles(encoder = { size, _ -> if (size == proxy) null else 50_000 }).isEmpty())
        assertTrue(profiles(encoder = { _, _ -> 1_999 }).isEmpty())
    }

    @Test
    fun supportsSixtyFpsWithIntegerNsRounding() {
        val faster = profiles(
            lens = lens.copy(aeFpsRanges = listOf(30..30, 60..60)),
            frames = mapOf(uhd to 33_333_334L, hd to 16_666_667L, proxy to 16_666_667L),
        )
        assertEquals(listOf("1080p", "720p"), faster.filter { it.fps == 60 }.map { it.masterRes })
        assertEquals(3, faster.count { it.fps == 30 })
    }
}
