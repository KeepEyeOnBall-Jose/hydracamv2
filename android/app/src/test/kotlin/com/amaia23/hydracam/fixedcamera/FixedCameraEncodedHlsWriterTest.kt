package com.amaia23.hydracam.fixedcamera

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FixedCameraEncodedHlsWriterTest {
    @Test
    fun writeFinalizedBundleCreatesFragmentedMp4HlsFromEncodedSamples() {
        val root = Files.createTempDirectory("hydracam-encoded-hls-writer-test").toFile()
        val outputDirectory = File(root, "game-1-camera-a")
        val avcConfig = FixedCameraH264AvcConfig.fromCsd(
            csd0 = annexB(SYNTHETIC_SPS),
            csd1 = annexB(SYNTHETIC_PPS),
        )

        val result = FixedCameraEncodedHlsWriter.writeFinalizedBundle(
            request = FixedCameraLocalHlsRecorder.Request(
                sessionGuid = "session-123",
                deviceId = "fixed-court-a",
                recordingId = "game-1-camera-a",
                targetDurationSeconds = 1,
                width = 1_920,
                height = 1_080,
                frameRate = 30,
                includeAudio = false,
            ),
            outputDirectory = outputDirectory,
            startedAt = "2026-06-19T10:32:00.000Z",
            finalizedAt = "2026-06-19T10:32:02.000Z",
            elapsedMillis = 2_000,
            avcConfig = avcConfig,
            videoSamples = listOf(
                FixedCameraEncodedHlsWriter.VideoSample(
                    presentationTimeUs = 0,
                    data = lengthPrefixedNal(0x65, 0x11, 0x22, 0x33),
                    isSyncSample = true,
                ),
                FixedCameraEncodedHlsWriter.VideoSample(
                    presentationTimeUs = 1_000_000,
                    data = lengthPrefixedNal(0x41, 0x44, 0x55, 0x66),
                    isSyncSample = false,
                ),
            ),
            audioSamples = emptyList(),
            recorderMode = "camera2_hls",
            syncConfidence = "device_clock",
        )

        assertEquals(FixedCameraLocalHlsRecorder.State.FINALIZED, result.state)
        assertEquals(2, result.chunkPaths.size)
        assertTrue(File(result.initPath!!).exists())
        assertTrue(File(result.playlistPath!!).exists())
        result.chunkPaths.forEach { path -> assertTrue(File(path).exists()) }

        val playlist = File(result.playlistPath!!).readText()
        assertTrue(playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""))
        assertTrue(playlist.contains("fixed-court-a-game-1-camera-a-00000000.m4s"))
        assertTrue(playlist.contains("fixed-court-a-game-1-camera-a-00000001.m4s"))
        assertTrue(playlist.contains("#EXT-X-ENDLIST"))
        assertTrue(result.nativeTimingMetadataJson!!.contains("\"recorderMode\":\"camera2_hls\""))
        assertTrue(result.nativeTimingMetadataJson!!.contains("\"videoSampleCount\":2"))
    }

    private fun lengthPrefixedNal(vararg bytes: Int): ByteArray =
        byteArrayOf(0x00, 0x00, 0x00, bytes.size.toByte()) +
            bytes.map { it.toByte() }.toByteArray()

    private fun annexB(nalUnit: ByteArray): ByteArray =
        byteArrayOf(0x00, 0x00, 0x00, 0x01) + nalUnit

    private companion object {
        val SYNTHETIC_SPS = byteArrayOf(
            0x67,
            0x64,
            0x00,
            0x1F,
            0xAC.toByte(),
            0xD9.toByte(),
            0x40,
            0x78,
        )
        val SYNTHETIC_PPS = byteArrayOf(
            0x68,
            0xEE.toByte(),
            0x3C,
            0x80.toByte(),
        )
    }
}
