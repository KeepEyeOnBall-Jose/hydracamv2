package com.amaia23.hydracam.fixedcamera

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FixedCameraMp4InitSegmentWriterTest {
    @Test
    fun writeCreatesFragmentedMp4InitSegmentWithVideoAndAudioTracks() {
        val root = Files.createTempDirectory("hydracam-mp4-init-test").toFile()
        val file = root.resolve("init.mp4")

        FixedCameraMp4InitSegmentWriter.write(
            file = file,
            width = 1_920,
            height = 1_080,
            avcConfig = byteArrayOf(1, 0x64, 0, 0x1F, 0xFF.toByte(), 0xE0.toByte()),
            sampleRate = 48_000,
            channelCount = 1,
            audioBitRate = 128_000,
        )

        val bytes = file.readBytes()
        assertEquals(listOf("ftyp", "moov"), topLevelBoxTypes(bytes))
        assertEquals(2, bytes.countAscii("trak"))
        assertEquals(2, bytes.countAscii("trex"))
        assertTrue(bytes.indexOfAscii("mvex") > 0)
        assertTrue(bytes.indexOfAscii("vide") > 0)
        assertTrue(bytes.indexOfAscii("soun") > 0)
        assertTrue(bytes.indexOfAscii("avc1") > 0)
        assertTrue(bytes.indexOfAscii("avcC") > 0)
        assertTrue(bytes.indexOfAscii("mp4a") > 0)
        assertTrue(bytes.indexOfAscii("esds") > 0)
    }

    @Test
    fun writeOmitsAudioTrackWhenChannelCountIsZero() {
        val root = Files.createTempDirectory("hydracam-mp4-init-no-audio-test").toFile()
        val file = root.resolve("init.mp4")

        FixedCameraMp4InitSegmentWriter.write(
            file = file,
            width = 1_920,
            height = 1_080,
            avcConfig = byteArrayOf(1, 0x64, 0, 0x1F, 0xFF.toByte(), 0xE0.toByte()),
            sampleRate = 48_000,
            channelCount = 0,
            audioBitRate = 128_000,
        )

        val bytes = file.readBytes()
        assertEquals(listOf("ftyp", "moov"), topLevelBoxTypes(bytes))
        assertEquals(1, bytes.countAscii("trak"))
        assertEquals(1, bytes.countAscii("trex"))
        assertTrue(bytes.indexOfAscii("avc1") > 0)
        assertEquals(-1, bytes.indexOfAscii("mp4a"))
        assertEquals(-1, bytes.indexOfAscii("esds"))
    }

    private fun topLevelBoxTypes(bytes: ByteArray): List<String> {
        val types = mutableListOf<String>()
        var offset = 0
        while (offset + 8 <= bytes.size) {
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

    private fun ByteArray.indexOfAscii(value: String): Int =
        toString(Charsets.ISO_8859_1).indexOf(value)

    private fun ByteArray.countAscii(value: String): Int {
        val text = toString(Charsets.ISO_8859_1)
        var count = 0
        var index = text.indexOf(value)
        while (index >= 0) {
            count += 1
            index = text.indexOf(value, index + value.length)
        }
        return count
    }
}
