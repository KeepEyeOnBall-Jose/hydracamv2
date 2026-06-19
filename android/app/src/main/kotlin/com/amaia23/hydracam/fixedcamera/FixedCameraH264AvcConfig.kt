package com.amaia23.hydracam.fixedcamera

import java.io.ByteArrayOutputStream

object FixedCameraH264AvcConfig {
    fun fromCsd(csd0: ByteArray, csd1: ByteArray? = null): ByteArray {
        val csd0Units = nalUnits(csd0)
        val csd1Units = csd1?.let(::nalUnits).orEmpty()
        val allUnits = csd0Units + csd1Units
        val sps = allUnits.firstOrNull { it.nalType == NAL_TYPE_SPS }?.payload
            ?: error("H.264 SPS not found in MediaCodec csd buffers.")
        val pps = allUnits.firstOrNull { it.nalType == NAL_TYPE_PPS }?.payload
            ?: error("H.264 PPS not found in MediaCodec csd buffers.")
        require(sps.size >= 4) {
            "H.264 SPS must include profile, compatibility, and level bytes."
        }

        return ByteArrayOutputStream().apply {
            write(AVC_CONFIG_VERSION)
            write(sps[1].toInt() and 0xFF)
            write(sps[2].toInt() and 0xFF)
            write(sps[3].toInt() and 0xFF)
            write(0xFC or (NAL_LENGTH_SIZE_BYTES - 1))
            write(0xE0 or 1)
            writeUInt16(sps.size)
            write(sps)
            write(1)
            writeUInt16(pps.size)
            write(pps)
        }.toByteArray()
    }

    private data class NalUnit(
        val payload: ByteArray,
    ) {
        val nalType: Int = payload.first().toInt() and 0x1F
    }

    private fun nalUnits(bytes: ByteArray): List<NalUnit> {
        val ranges = annexBPayloadRanges(bytes)
        if (ranges.isEmpty()) {
            return listOf(NalUnit(bytes))
        }
        return ranges
            .map { range -> bytes.copyOfRange(range.startInclusive, range.endExclusive) }
            .filter { it.isNotEmpty() }
            .map(::NalUnit)
    }

    private data class PayloadRange(
        val startInclusive: Int,
        val endExclusive: Int,
    )

    private fun annexBPayloadRanges(bytes: ByteArray): List<PayloadRange> {
        val startCodes = mutableListOf<Pair<Int, Int>>()
        var index = 0
        while (index <= bytes.size - 3) {
            val length = startCodeLengthAt(bytes, index)
            if (length > 0) {
                startCodes += index to length
                index += length
            } else {
                index += 1
            }
        }
        if (startCodes.isEmpty()) {
            return emptyList()
        }

        return startCodes.mapIndexed { startIndex, (codeOffset, codeLength) ->
            val payloadStart = codeOffset + codeLength
            val payloadEnd = if (startIndex + 1 < startCodes.size) {
                startCodes[startIndex + 1].first
            } else {
                bytes.size
            }
            PayloadRange(payloadStart, payloadEnd)
        }
    }

    private fun startCodeLengthAt(bytes: ByteArray, offset: Int): Int {
        if (
            offset + 4 <= bytes.size &&
            bytes[offset] == ZERO &&
            bytes[offset + 1] == ZERO &&
            bytes[offset + 2] == ZERO &&
            bytes[offset + 3] == ONE
        ) {
            return 4
        }
        if (
            offset + 3 <= bytes.size &&
            bytes[offset] == ZERO &&
            bytes[offset + 1] == ZERO &&
            bytes[offset + 2] == ONE
        ) {
            return 3
        }
        return 0
    }

    private fun ByteArrayOutputStream.writeUInt16(value: Int) {
        write((value ushr 8) and 0xFF)
        write(value and 0xFF)
    }

    private const val AVC_CONFIG_VERSION = 1
    private const val NAL_LENGTH_SIZE_BYTES = 4
    private const val NAL_TYPE_SPS = 7
    private const val NAL_TYPE_PPS = 8
    private const val ZERO: Byte = 0
    private const val ONE: Byte = 1
}
