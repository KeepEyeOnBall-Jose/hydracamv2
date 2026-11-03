package com.amaia23.hydracam.court

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

class MpegTsMuxerTest {
    private class Packet(val bytes: ByteArray) {
        val pid: Int get() = ((bytes[1].toInt() and 0x1F) shl 8) or (bytes[2].toInt() and 0xFF)
        val payloadStart: Boolean get() = bytes[1].toInt() and 0x40 != 0
        val continuity: Int get() = bytes[3].toInt() and 0x0F
        val hasAdaptation: Boolean get() = bytes[3].toInt() and 0x20 != 0
        val payloadOffset: Int get() = if (hasAdaptation) 5 + (bytes[4].toInt() and 0xFF) else 4
        val payload: ByteArray get() = bytes.copyOfRange(payloadOffset, bytes.size)
    }

    private fun mux(hasAudio: Boolean, block: (MpegTsMuxer) -> Unit): List<Packet> {
        val out = ByteArrayOutputStream()
        val muxer = MpegTsMuxer(hasAudio)
        muxer.attach(out)
        block(muxer)
        val bytes = out.toByteArray()
        assertEquals(0, bytes.size % MpegTsMuxer.PACKET_SIZE)
        assertEquals(muxer.packetsWritten, (bytes.size / MpegTsMuxer.PACKET_SIZE).toLong())
        return (0 until bytes.size / MpegTsMuxer.PACKET_SIZE).map { index ->
            val packet = bytes.copyOfRange(index * MpegTsMuxer.PACKET_SIZE, (index + 1) * MpegTsMuxer.PACKET_SIZE)
            assertEquals(0x47.toByte(), packet[0])
            Packet(packet)
        }
    }

    /** PSI section after the pointer field; CRC over section + CRC is 0 for CRC-32/MPEG-2. */
    private fun section(packet: Packet): ByteArray {
        val start = 5 + (packet.bytes[4].toInt() and 0xFF)
        val length = ((packet.bytes[start + 1].toInt() and 0x0F) shl 8) or (packet.bytes[start + 2].toInt() and 0xFF)
        return packet.bytes.copyOfRange(start, start + 3 + length)
    }

    @Test
    fun timestampRoundTripAndClockConversion() {
        for (value in listOf(0L, 1L, 63_000L, 8_589_934_591L, 123_456_789L)) {
            val encoded = MpegTsMuxer.encodeTimestamp(0x2, value)
            assertEquals(value, MpegTsMuxer.decodeTimestamp(encoded, 0))
            assertEquals(0x21, encoded[0].toInt() and 0xF1)
        }
        assertEquals(90_000L, MpegTsMuxer.usTo90k(1_000_000))
        // Truncates: 33 333 µs is 2 999.97 ticks.
        assertEquals(2_999L, MpegTsMuxer.usTo90k(33_333))
    }

    @Test
    fun crcMatchesKnownVector() {
        // CRC-32/MPEG-2 check value for "123456789".
        assertEquals(0x0376E6E7, MpegTsMuxer.crc32Mpeg("123456789".toByteArray()))
    }

    @Test
    fun keyframeStartsWithPatAndPmtWithValidCrc() {
        val packets =
            mux(hasAudio = false) { it.writeVideo(0, ByteArray(100) { 7 }, isKeyframe = true, videoConfig = null) }

        assertEquals(MpegTsMuxer.PAT_PID, packets[0].pid)
        assertEquals(MpegTsMuxer.PMT_PID, packets[1].pid)
        val pat = section(packets[0])
        val pmt = section(packets[1])
        assertEquals(0, MpegTsMuxer.crc32Mpeg(pat))
        assertEquals(0, MpegTsMuxer.crc32Mpeg(pmt))
        assertEquals(16, pat.size)
        // One elementary stream (H.264) without audio.
        assertEquals(12 + 5 + 4, pmt.size)
        assertEquals(MpegTsMuxer.STREAM_TYPE_H264, pmt[12].toInt() and 0xFF)
    }

    @Test
    fun pmtListsAudioOnlyWhenEnabled() {
        val packets = mux(hasAudio = true) { it.writeTables() }
        val pmt = section(packets[1])

        assertEquals(0, MpegTsMuxer.crc32Mpeg(pmt))
        assertEquals(12 + 10 + 4, pmt.size)
        assertEquals(MpegTsMuxer.STREAM_TYPE_AAC_ADTS, pmt[17].toInt() and 0xFF)
    }

    @Test
    fun videoPesCarriesPtsPcrAndRandomAccessOnKeyframe() {
        val ts90k = 270_000L
        val config = byteArrayOf(0, 0, 0, 1, 0x67, 1, 2, 0, 0, 0, 1, 0x68, 3)
        val frame = ByteArray(5_000) { (it % 251).toByte() }
        val packets = mux(hasAudio = false) { it.writeVideo(ts90k, frame, isKeyframe = true, videoConfig = config) }
        val video = packets.filter { it.pid == MpegTsMuxer.VIDEO_PID }
        val first = video.first()

        assertTrue(first.payloadStart)
        assertTrue(video.drop(1).none { it.payloadStart })
        assertEquals(0x50, first.bytes[5].toInt() and 0xFF)
        val pcr = ((first.bytes[6].toLong() and 0xFF) shl 25) or
            ((first.bytes[7].toLong() and 0xFF) shl 17) or
            ((first.bytes[8].toLong() and 0xFF) shl 9) or
            ((first.bytes[9].toLong() and 0xFF) shl 1) or
            ((first.bytes[10].toLong() and 0xFF) shr 7)
        assertEquals(ts90k, pcr)
        video.forEachIndexed { index, packet -> assertEquals(index % 16, packet.continuity) }

        val pes = video.fold(ByteArray(0)) { acc, packet -> acc + packet.payload }
        assertEquals(ts90k + MpegTsMuxer.PTS_DELAY_90K, MpegTsMuxer.decodeTimestamp(pes, 9))
        // Unbounded video PES: length 0.
        assertEquals(0, pes[4].toInt() or pes[5].toInt())
        val aud = byteArrayOf(0, 0, 0, 1, 0x09, 0xF0.toByte())
        assertArrayEquals(aud + config + frame, pes.copyOfRange(14, pes.size))
    }

    @Test
    fun deltaFrameHasNoTablesNorConfig() {
        val config = byteArrayOf(0, 0, 0, 1, 0x67)
        val frame = ByteArray(50) { 3 }
        val packets = mux(hasAudio = false) { it.writeVideo(3_000, frame, isKeyframe = false, videoConfig = config) }

        assertEquals(listOf(MpegTsMuxer.VIDEO_PID), packets.map { it.pid })
        val pes = packets.single().payload
        assertEquals(0, packets.single().bytes[5].toInt() and 0x40)
        assertEquals(6 + frame.size, pes.size - 14)
    }

    @Test
    fun audioIsWrittenOnlyWhenEnabled() {
        val aac = ByteArray(300) { 1 }
        assertTrue(mux(hasAudio = false) { it.writeAudio(0, aac) }.isEmpty())

        val packets = mux(hasAudio = true) { it.writeAudio(1_920, aac) }
        assertTrue(packets.all { it.pid == MpegTsMuxer.AUDIO_PID })
        val pes = packets.fold(ByteArray(0)) { acc, packet -> acc + packet.payload }
        val length = ((pes[4].toInt() and 0xFF) shl 8) or (pes[5].toInt() and 0xFF)
        assertEquals(pes.size - 6, length)
        assertEquals(1_920 + MpegTsMuxer.PTS_DELAY_90K, MpegTsMuxer.decodeTimestamp(pes, 9))
        // ADTS sync word, then the raw frame.
        assertEquals(0xFF, pes[14].toInt() and 0xFF)
        assertEquals(0xF1, pes[15].toInt() and 0xFF)
        assertEquals(7 + aac.size, pes.size - 14)
    }
}
