package com.amaia23.hydracam.fixedcamera

import java.io.ByteArrayOutputStream

object FixedCameraH264SampleFormatter {
    fun toLengthPrefixedSample(bytes: ByteArray): ByteArray {
        if (isLengthPrefixed(bytes)) {
            return bytes
        }

        val nalUnits = annexBNalUnits(bytes)
        if (nalUnits.isEmpty()) {
            return bytes
        }
        val mediaNalUnits = nalUnits.filterNot { nalUnit ->
            val nalType = nalUnit.first().toInt() and 0x1F
            nalType == NAL_TYPE_SPS || nalType == NAL_TYPE_PPS
        }
        require(mediaNalUnits.isNotEmpty()) {
            "H.264 media sample contains no non-parameter-set NAL units."
        }

        return ByteArrayOutputStream().apply {
            mediaNalUnits.forEach { nalUnit ->
                writeUInt32(nalUnit.size)
                write(nalUnit)
            }
        }.toByteArray()
    }

    private fun isLengthPrefixed(bytes: ByteArray): Boolean {
        var offset = 0
        while (offset + NAL_LENGTH_BYTES <= bytes.size) {
            val length = bytes.readUInt32(offset)
            if (length <= 0 || offset + NAL_LENGTH_BYTES + length > bytes.size) {
                return false
            }
            offset += NAL_LENGTH_BYTES + length
        }
        return offset == bytes.size && bytes.isNotEmpty()
    }

    private fun annexBNalUnits(bytes: ByteArray): List<ByteArray> {
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

        return startCodes.mapIndexedNotNull { startIndex, (codeOffset, codeLength) ->
            val payloadStart = codeOffset + codeLength
            val payloadEnd = if (startIndex + 1 < startCodes.size) {
                startCodes[startIndex + 1].first
            } else {
                bytes.size
            }
            if (payloadEnd <= payloadStart) {
                null
            } else {
                bytes.copyOfRange(payloadStart, payloadEnd)
            }
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

    private fun ByteArray.readUInt32(offset: Int): Int =
        ((this[offset].toInt() and 0xFF) shl 24) or
            ((this[offset + 1].toInt() and 0xFF) shl 16) or
            ((this[offset + 2].toInt() and 0xFF) shl 8) or
            (this[offset + 3].toInt() and 0xFF)

    private fun ByteArrayOutputStream.writeUInt32(value: Int) {
        write((value ushr 24) and 0xFF)
        write((value ushr 16) and 0xFF)
        write((value ushr 8) and 0xFF)
        write(value and 0xFF)
    }

    private const val NAL_LENGTH_BYTES = 4
    private const val NAL_TYPE_SPS = 7
    private const val NAL_TYPE_PPS = 8
    private const val ZERO: Byte = 0
    private const val ONE: Byte = 1
}
