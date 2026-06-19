package com.amaia23.hydracam.fixedcamera

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class FixedCameraH264AvcConfigTest {
    @Test
    fun fromAnnexBCsdBuildsAvcDecoderConfigurationRecord() {
        val sps = byteArrayOf(
            0x67,
            0x64,
            0x00,
            0x1F,
            0xAC.toByte(),
            0xD9.toByte(),
            0x40,
            0x78,
        )
        val pps = byteArrayOf(
            0x68,
            0xEE.toByte(),
            0x3C,
            0x80.toByte(),
        )

        val avcConfig = FixedCameraH264AvcConfig.fromCsd(
            csd0 = annexB(sps),
            csd1 = annexB(pps),
        )

        assertArrayEquals(avcConfigRecord(sps, pps), avcConfig)
    }

    @Test
    fun fromCombinedCsd0BuildsAvcDecoderConfigurationRecord() {
        val sps = byteArrayOf(
            0x67,
            0x64,
            0x00,
            0x28,
            0xAC.toByte(),
            0x2C,
            0xA5.toByte(),
            0x01,
        )
        val pps = byteArrayOf(
            0x68,
            0xCE.toByte(),
            0x3C,
            0x80.toByte(),
        )

        val avcConfig = FixedCameraH264AvcConfig.fromCsd(
            csd0 = annexB(sps, startCode = byteArrayOf(0x00, 0x00, 0x01)) + annexB(pps),
        )

        assertArrayEquals(avcConfigRecord(sps, pps), avcConfig)
    }

    private fun avcConfigRecord(sps: ByteArray, pps: ByteArray): ByteArray =
        byteArrayOf(
            0x01,
            sps[1],
            sps[2],
            sps[3],
            0xFF.toByte(),
            0xE1.toByte(),
            0x00,
            sps.size.toByte(),
        ) + sps + byteArrayOf(
            0x01,
            0x00,
            pps.size.toByte(),
        ) + pps

    private fun annexB(
        nalUnit: ByteArray,
        startCode: ByteArray = byteArrayOf(0x00, 0x00, 0x00, 0x01),
    ): ByteArray = startCode + nalUnit
}
