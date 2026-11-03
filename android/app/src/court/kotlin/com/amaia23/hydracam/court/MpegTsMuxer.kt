package com.amaia23.hydracam.court

import java.io.ByteArrayOutputStream
import java.io.OutputStream

/**
 * Minimal streaming MPEG-TS muxer: one H.264 program, optional AAC (ADTS) audio.
 *
 * - PAT/PMT before every keyframe, so each segment file starts decodable.
 * - Each access unit gets an AUD; keyframes get SPS/PPS ([videoConfig]) in front.
 * - PCR rides on video; PTS = PCR + [PTS_DELAY_90K] (no B-frames, so DTS == PTS is omitted).
 *
 * Not thread-safe; [TsSegmenter] serializes access.
 */
class MpegTsMuxer(private val hasAudio: Boolean) {
    private val continuity = IntArray(0x2000)
    private var out: OutputStream? = null
    var packetsWritten: Long = 0
        private set

    fun attach(stream: OutputStream) {
        out = stream
    }

    fun writeTables() {
        writeSection(PAT_PID, patSection())
        writeSection(PMT_PID, pmtSection())
    }

    /**
     * [timestamp90k] is the frame time on the 90 kHz clock, already relative to the session base.
     * [annexB] is the encoder output (Annex-B start codes).
     */
    fun writeVideo(timestamp90k: Long, annexB: ByteArray, isKeyframe: Boolean, videoConfig: ByteArray?) {
        if (isKeyframe) {
            writeTables()
        }
        val config = if (isKeyframe) videoConfig else null
        val accessUnit = ByteArray(AUD.size + (config?.size ?: 0) + annexB.size)
        System.arraycopy(AUD, 0, accessUnit, 0, AUD.size)
        var offset = AUD.size
        if (config != null) {
            System.arraycopy(config, 0, accessUnit, offset, config.size)
            offset += config.size
        }
        System.arraycopy(annexB, 0, accessUnit, offset, annexB.size)
        val pes = pesPacket(VIDEO_STREAM_ID, timestamp90k + PTS_DELAY_90K, accessUnit, boundedLength = false)
        writePes(VIDEO_PID, pes, pcr90k = timestamp90k, randomAccess = isKeyframe)
    }

    /** [aacRaw] is one raw AAC-LC frame (no ADTS) from MediaCodec; 48 kHz mono. */
    fun writeAudio(timestamp90k: Long, aacRaw: ByteArray) {
        if (!hasAudio) {
            return
        }
        val frame = adtsHeader(aacRaw.size) + aacRaw
        val pes = pesPacket(AUDIO_STREAM_ID, timestamp90k + PTS_DELAY_90K, frame, boundedLength = true)
        writePes(AUDIO_PID, pes, pcr90k = null, randomAccess = false)
    }

    private fun writeSection(pid: Int, section: ByteArray) {
        val packet = ByteArray(PACKET_SIZE) { 0xFF.toByte() }
        packet[0] = SYNC_BYTE
        packet[1] = (0x40 or ((pid shr 8) and 0x1F)).toByte()
        packet[2] = (pid and 0xFF).toByte()
        packet[3] = (0x10 or nextContinuity(pid)).toByte()
        packet[4] = 0 // pointer_field
        System.arraycopy(section, 0, packet, 5, section.size)
        emit(packet)
    }

    private fun writePes(pid: Int, pes: ByteArray, pcr90k: Long?, randomAccess: Boolean) {
        var offset = 0
        while (offset < pes.size) {
            val first = offset == 0
            val packet = ByteArray(PACKET_SIZE)
            packet[0] = SYNC_BYTE
            packet[1] = ((if (first) 0x40 else 0) or ((pid shr 8) and 0x1F)).toByte()
            packet[2] = (pid and 0xFF).toByte()
            // PCR and random_access ride only on the packet that starts the PES.
            val pcr = if (first) pcr90k else null
            val ra = first && randomAccess
            val adaptation = adaptationLength(pes.size - offset, pcr, ra)
            packet[3] = ((if (adaptation > 0) 0x30 else 0x10) or nextContinuity(pid)).toByte()
            val cursor = if (adaptation > 0) writeAdaptation(packet, adaptation, pcr, ra) else 4
            val payloadLength = PAYLOAD_SIZE - adaptation
            System.arraycopy(pes, offset, packet, cursor, payloadLength)
            offset += payloadLength
            emit(packet)
        }
    }

    /** Adaptation field bytes (length byte included): flags + PCR when wanted, grown to stuff a short tail. */
    private fun adaptationLength(remaining: Int, pcr90k: Long?, randomAccess: Boolean): Int {
        val wanted = if (pcr90k != null || randomAccess) 2 + (if (pcr90k != null) 6 else 0) else 0
        val capacity = PAYLOAD_SIZE - wanted
        return if (remaining < capacity) wanted + capacity - remaining else wanted
    }

    /** Writes a [total]-byte adaptation field at offset 4; returns where the payload starts. */
    private fun writeAdaptation(packet: ByteArray, total: Int, pcr90k: Long?, randomAccess: Boolean): Int {
        val body = total - 1
        packet[4] = body.toByte()
        if (body > 0) {
            var flags = 0
            if (randomAccess) {
                flags = flags or 0x40
            }
            if (pcr90k != null) {
                flags = flags or 0x10
                writePcr(packet, 6, pcr90k)
            }
            packet[5] = flags.toByte()
            packet.fill(0xFF.toByte(), if (pcr90k != null) 12 else 6, 4 + total)
        }
        return 4 + total
    }

    private fun emit(packet: ByteArray) {
        val stream = out ?: error("No output attached.")
        stream.write(packet)
        packetsWritten += 1
    }

    private fun nextContinuity(pid: Int): Int {
        val value = continuity[pid]
        continuity[pid] = (value + 1) and 0x0F
        return value
    }

    private fun patSection(): ByteArray {
        val body = byteArrayOf(
            0x00, // table_id
            0xB0.toByte(), 0x0D, // section_syntax_indicator=1, length 13
            0x00, 0x01, // transport_stream_id
            0xC1.toByte(), // version 0, current_next 1
            0x00, 0x00, // section_number, last_section_number
            0x00, 0x01, // program_number 1
            (0xE0 or (PMT_PID shr 8)).toByte(), (PMT_PID and 0xFF).toByte(),
        )
        return withCrc(body)
    }

    private fun pmtSection(): ByteArray {
        val streams = mutableListOf(STREAM_TYPE_H264 to VIDEO_PID)
        if (hasAudio) {
            streams += STREAM_TYPE_AAC_ADTS to AUDIO_PID
        }
        val sectionLength = 9 + 5 * streams.size + 4
        val body = ByteArrayOutputStream()
        body.write(0x02)
        body.write(0xB0 or (sectionLength shr 8))
        body.write(sectionLength and 0xFF)
        body.write(0x00)
        body.write(0x01) // program_number
        body.write(0xC1)
        body.write(0x00)
        body.write(0x00)
        body.write(0xE0 or (VIDEO_PID shr 8)) // PCR_PID
        body.write(VIDEO_PID and 0xFF)
        body.write(0xF0)
        body.write(0x00) // program_info_length 0
        for ((streamType, pid) in streams) {
            body.write(streamType)
            body.write(0xE0 or (pid shr 8))
            body.write(pid and 0xFF)
            body.write(0xF0)
            body.write(0x00)
        }
        return withCrc(body.toByteArray())
    }

    private fun withCrc(section: ByteArray): ByteArray {
        val crc = crc32Mpeg(section)
        return section + byteArrayOf(
            (crc ushr 24).toByte(),
            (crc ushr 16).toByte(),
            (crc ushr 8).toByte(),
            crc.toByte(),
        )
    }

    private fun adtsHeader(payloadLength: Int): ByteArray {
        val frameLength = payloadLength + 7
        val profile = 1 // AAC LC (object type 2) - 1
        val channels = 1
        return byteArrayOf(
            0xFF.toByte(),
            0xF1.toByte(),
            ((profile shl 6) or (ADTS_FREQUENCY_INDEX_48K shl 2) or (channels shr 2)).toByte(),
            (((channels and 3) shl 6) or (frameLength shr 11)).toByte(),
            ((frameLength shr 3) and 0xFF).toByte(),
            (((frameLength and 7) shl 5) or 0x1F).toByte(),
            0xFC.toByte(),
        )
    }

    companion object {
        const val PACKET_SIZE = 188
        const val PAYLOAD_SIZE = 184
        const val PAT_PID = 0x0000
        const val PMT_PID = 0x1000
        const val VIDEO_PID = 0x0100
        const val AUDIO_PID = 0x0101
        const val STREAM_TYPE_H264 = 0x1B
        const val STREAM_TYPE_AAC_ADTS = 0x0F
        const val PTS_DELAY_90K = 63_000L
        private const val SYNC_BYTE = 0x47.toByte()
        private const val VIDEO_STREAM_ID = 0xE0
        private const val AUDIO_STREAM_ID = 0xC0
        private const val ADTS_FREQUENCY_INDEX_48K = 3
        private val AUD = byteArrayOf(0, 0, 0, 1, 0x09, 0xF0.toByte())

        fun usTo90k(us: Long): Long = us * 9 / 100

        fun pesPacket(streamId: Int, pts90k: Long, payload: ByteArray, boundedLength: Boolean): ByteArray {
            val headerDataLength = 5
            val pesLength = 3 + headerDataLength + payload.size
            val lengthField = if (boundedLength && pesLength <= 0xFFFF) pesLength else 0
            val header = byteArrayOf(
                0x00, 0x00, 0x01,
                streamId.toByte(),
                (lengthField shr 8).toByte(), (lengthField and 0xFF).toByte(),
                0x84.toByte(), // '10' marker, data_alignment_indicator
                0x80.toByte(), // PTS only
                headerDataLength.toByte(),
            )
            return header + encodeTimestamp(0x2, pts90k) + payload
        }

        fun encodeTimestamp(prefix: Int, value90k: Long): ByteArray {
            val ts = value90k and 0x1FFFFFFFFL
            return byteArrayOf(
                ((prefix shl 4) or (((ts shr 30) and 0x07).toInt() shl 1) or 1).toByte(),
                ((ts shr 22) and 0xFF).toByte(),
                ((((ts shr 15) and 0x7F).toInt() shl 1) or 1).toByte(),
                ((ts shr 7) and 0xFF).toByte(),
                (((ts and 0x7F).toInt() shl 1) or 1).toByte(),
            )
        }

        fun decodeTimestamp(bytes: ByteArray, offset: Int): Long {
            val b0 = bytes[offset].toLong() and 0xFF
            val b1 = bytes[offset + 1].toLong() and 0xFF
            val b2 = bytes[offset + 2].toLong() and 0xFF
            val b3 = bytes[offset + 3].toLong() and 0xFF
            val b4 = bytes[offset + 4].toLong() and 0xFF
            return ((b0 shr 1) and 0x07 shl 30) or (b1 shl 22) or ((b2 shr 1) shl 15) or (b3 shl 7) or (b4 shr 1)
        }

        private fun writePcr(packet: ByteArray, offset: Int, pcr90k: Long) {
            val base = pcr90k and 0x1FFFFFFFFL
            packet[offset] = (base shr 25).toByte()
            packet[offset + 1] = (base shr 17).toByte()
            packet[offset + 2] = (base shr 9).toByte()
            packet[offset + 3] = (base shr 1).toByte()
            packet[offset + 4] = (((base and 1).toInt() shl 7) or 0x7E).toByte()
            packet[offset + 5] = 0
        }

        /** CRC-32/MPEG-2: poly 0x04C11DB7, init 0xFFFFFFFF, no reflection, no final xor. */
        fun crc32Mpeg(data: ByteArray, length: Int = data.size): Int {
            var crc = -1
            for (index in 0 until length) {
                crc = crc xor ((data[index].toInt() and 0xFF) shl 24)
                repeat(8) {
                    crc = if (crc and Int.MIN_VALUE != 0) (crc shl 1) xor 0x04C11DB7 else crc shl 1
                }
            }
            return crc
        }
    }
}
