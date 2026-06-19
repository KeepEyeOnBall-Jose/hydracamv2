package com.amaia23.hydracam.fixedcamera

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class FixedCameraH264SampleFormatterTest {
    @Test
    fun toLengthPrefixedSampleDropsAnnexBParameterSets() {
        val idr = byteArrayOf(0x65, 0x11, 0x22, 0x33)

        val sample = FixedCameraH264SampleFormatter.toLengthPrefixedSample(
            annexB(SPS) + annexB(PPS) + annexB(idr),
        )

        assertArrayEquals(lengthPrefixed(idr), sample)
    }

    @Test
    fun toLengthPrefixedSampleKeepsExistingLengthPrefixedSample() {
        val input = lengthPrefixed(byteArrayOf(0x41, 0x44, 0x55, 0x66))

        val sample = FixedCameraH264SampleFormatter.toLengthPrefixedSample(input)

        assertArrayEquals(input, sample)
    }

    private fun annexB(nalUnit: ByteArray): ByteArray =
        byteArrayOf(0x00, 0x00, 0x00, 0x01) + nalUnit

    private fun lengthPrefixed(nalUnit: ByteArray): ByteArray =
        byteArrayOf(
            0x00,
            0x00,
            0x00,
            nalUnit.size.toByte(),
        ) + nalUnit

    private companion object {
        val SPS = byteArrayOf(
            0x67,
            0x64,
            0x00,
            0x1F,
            0xAC.toByte(),
            0xD9.toByte(),
            0x40,
            0x78,
        )
        val PPS = byteArrayOf(
            0x68,
            0xEE.toByte(),
            0x3C,
            0x80.toByte(),
        )
    }
}
