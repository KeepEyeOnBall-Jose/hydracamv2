package com.amaia23.hydracam.fixedcamera

import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FixedCameraMp4FragmentWriterTest {
    @Test
    fun writeCreatesFragmentedMp4MediaSegmentWithVideoAndAudioSamples() {
        val root = Files.createTempDirectory("hydracam-mp4-fragment-test").toFile()
        val file = root.resolve("nested/fixed-court-a-game-1-00000000.m4s")
        val videoSample = byteArrayOf(0, 0, 0, 4, 0x65, 0x11, 0x22, 0x33)
        val audioSample = byteArrayOf(0x21, 0x10, 0x56, 0xE5.toByte())

        FixedCameraMp4FragmentWriter.write(
            file = file,
            sequenceNumber = 7,
            fragments = listOf(
                FixedCameraMp4FragmentWriter.TrackFragment(
                    trackId = 1,
                    baseMediaDecodeTime = 180_000,
                    samples = listOf(
                        FixedCameraMp4FragmentWriter.Sample.video(
                            duration = 3_000,
                            data = videoSample,
                            isSyncSample = true,
                        ),
                    ),
                ),
                FixedCameraMp4FragmentWriter.TrackFragment(
                    trackId = 2,
                    baseMediaDecodeTime = 96_000,
                    samples = listOf(
                        FixedCameraMp4FragmentWriter.Sample.audio(
                            duration = 1_024,
                            data = audioSample,
                        ),
                    ),
                ),
            ),
        )

        val bytes = file.readBytes()
        val topLevelBoxes = topLevelBoxes(bytes)
        assertEquals(listOf("styp", "moof", "mdat"), topLevelBoxes.map { it.type })
        assertEquals(2, bytes.countAscii("traf"))
        assertEquals(2, bytes.countAscii("tfdt"))
        assertEquals(2, bytes.countAscii("trun"))
        assertTrue(bytes.indexOfAscii("mfhd") > 0)
        assertTrue(bytes.indexOfAscii("tfhd") > 0)

        val moofSize = topLevelBoxes.first { it.type == "moof" }.size
        assertEquals(
            listOf(moofSize + BOX_HEADER_BYTES, moofSize + BOX_HEADER_BYTES + videoSample.size),
            trunDataOffsets(bytes),
        )
        assertArrayEquals(videoSample + audioSample, topLevelBoxPayload(bytes, "mdat"))
    }

    private data class BoxInfo(
        val type: String,
        val start: Int,
        val size: Int,
    )

    private fun topLevelBoxes(bytes: ByteArray): List<BoxInfo> {
        val boxes = mutableListOf<BoxInfo>()
        var offset = 0
        while (offset + BOX_HEADER_BYTES <= bytes.size) {
            val size = bytes.readUInt32(offset)
            val type = bytes.copyOfRange(offset + 4, offset + 8).toString(Charsets.US_ASCII)
            boxes += BoxInfo(type = type, start = offset, size = size)
            offset += size
        }
        return boxes
    }

    private fun trunDataOffsets(bytes: ByteArray): List<Int> {
        val text = bytes.toString(Charsets.ISO_8859_1)
        val offsets = mutableListOf<Int>()
        var typeIndex = text.indexOf("trun")
        while (typeIndex >= 0) {
            val payloadStart = typeIndex + 4
            offsets += bytes.readUInt32(payloadStart + 8)
            typeIndex = text.indexOf("trun", typeIndex + 4)
        }
        return offsets
    }

    private fun topLevelBoxPayload(bytes: ByteArray, type: String): ByteArray {
        val box = topLevelBoxes(bytes).first { it.type == type }
        return bytes.copyOfRange(box.start + BOX_HEADER_BYTES, box.start + box.size)
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

    private companion object {
        const val BOX_HEADER_BYTES = 8
    }
}
