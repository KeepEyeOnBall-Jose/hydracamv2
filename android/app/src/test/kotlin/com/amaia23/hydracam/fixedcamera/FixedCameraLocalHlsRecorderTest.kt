package com.amaia23.hydracam.fixedcamera

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FixedCameraLocalHlsRecorderTest {
    @Test
    fun startThenStopWritesSyntheticHlsBundle() {
        val root = Files.createTempDirectory("hydracam-local-hls-recorder-test").toFile()
        val clockValues = mutableListOf(1_781_865_120_000L, 1_781_865_124_000L)
        val recorder = FixedCameraLocalHlsRecorder(
            outputRoot = root,
            clockMillis = { clockValues.removeAt(0) },
        )

        val started = recorder.start(
            FixedCameraLocalHlsRecorder.Request(
                sessionGuid = "session-123",
                deviceId = "fixed-court-a",
                recordingId = "game-1-camera-a",
                targetDurationSeconds = 2,
                width = 1_920,
                height = 1_080,
                frameRate = 30,
                includeAudio = true,
            ),
        )

        assertEquals("game-1-camera-a", started.recordingId)
        assertEquals(FixedCameraLocalHlsRecorder.State.RECORDING, started.state)
        assertTrue(started.recordingDirectoryPath.endsWith("game-1-camera-a"))
        assertEquals("2026-06-19T10:32:00.000Z", started.startedAt)

        val finalized = recorder.stop("game-1-camera-a")

        assertEquals(FixedCameraLocalHlsRecorder.State.FINALIZED, finalized.state)
        assertEquals("2026-06-19T10:32:04.000Z", finalized.finalizedAt)
        assertEquals(4.0, finalized.durationSeconds!!, 0.001)
        assertEquals(2, finalized.targetDurationSeconds)
        assertEquals(2, finalized.chunkPaths.size)
        assertTrue(File(finalized.playlistPath!!).exists())
        assertTrue(File(finalized.initPath!!).exists())
        finalized.chunkPaths.forEach { path -> assertTrue(File(path).exists()) }
        assertTrue(finalized.nativeTimingMetadataJson!!.contains("\"recorderMode\":\"synthetic_local\""))
        assertTrue(finalized.nativeTimingMetadataJson!!.contains("\"syncConfidence\":\"synthetic\""))

        val playlist = File(finalized.playlistPath!!).readText()
        assertTrue(playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""))
        assertTrue(playlist.contains("fixed-court-a-game-1-camera-a-00000000.m4s"))
        assertTrue(playlist.contains("fixed-court-a-game-1-camera-a-00000001.m4s"))
        assertTrue(playlist.contains("#EXT-X-ENDLIST"))

        assertEquals(listOf("ftyp", "moov"), topLevelBoxTypes(File(finalized.initPath!!)))
        finalized.chunkPaths.forEach { path ->
            assertEquals(listOf("styp", "moof", "mdat"), topLevelBoxTypes(File(path)))
        }
    }

    private fun topLevelBoxTypes(file: File): List<String> {
        val bytes = file.readBytes()
        val types = mutableListOf<String>()
        var offset = 0
        while (offset + BOX_HEADER_BYTES <= bytes.size) {
            val size = bytes.readUInt32(offset)
            types += bytes.copyOfRange(offset + 4, offset + 8).toString(Charsets.US_ASCII)
            offset += size
        }
        return types
    }

    private fun ByteArray.readUInt32(offset: Int): Int =
        ((this[offset].toInt() and 0xFF) shl 24) or
            ((this[offset + 1].toInt() and 0xFF) shl 16) or
            ((this[offset + 2].toInt() and 0xFF) shl 8) or
            (this[offset + 3].toInt() and 0xFF)

    private companion object {
        const val BOX_HEADER_BYTES = 8
    }
}
