package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
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

    private fun section(packet: Packet): ByteArray {
        val start = 5 + (packet.bytes[4].toInt() and 0xFF)
        val length = ((packet.bytes[start + 1].toInt() and 0x0F) shl 8) or (packet.bytes[start + 2].toInt() and 0xFF)
        return packet.bytes.copyOfRange(start, start + 3 + length)
    }

    @Test
    fun timestampAndClockHelpersConvertAndRoundTrip() {
        for (value in listOf(0L, 1L, 63_000L, 8_589_934_591L, 123_456_789L)) {
            val encoded = MpegTsMuxer.encodeTimestamp(0x2, value)
            assertEquals(value, MpegTsMuxer.decodeTimestamp(encoded, 0))
            assertEquals(0x21, encoded[0].toInt() and 0xF1)
        }
        assertEquals(90_000L, MpegTsMuxer.usTo90k(1_000_000))
        assertEquals(2_999L, MpegTsMuxer.usTo90k(33_333))
        assertEquals(1_000L, MpegTsMuxer.ms(90_000L))
        assertEquals(0x0376E6E7, MpegTsMuxer.crc32Mpeg("123456789".toByteArray()))
    }

    @Test
    fun patPmtAndVideoAudioPacketsMatchIso13818Layout() {
        val packets = mux(hasAudio = true) { muxer ->
            muxer.writeVideo(
                270_000L,
                ByteArray(400) { (it % 251).toByte() },
                isKeyframe = true,
                videoConfig = byteArrayOf(0, 0, 0, 1, 0x67, 1, 2),
            )
            muxer.writeAudio(273_000L, ByteArray(100) { 1 })
        }

        assertEquals(MpegTsMuxer.PAT_PID, packets[0].pid)
        assertEquals(MpegTsMuxer.PMT_PID, packets[1].pid)
        assertEquals(0, MpegTsMuxer.crc32Mpeg(section(packets[0])))
        val pmt = section(packets[1])
        assertEquals(0, MpegTsMuxer.crc32Mpeg(pmt))
        assertEquals(MpegTsMuxer.STREAM_TYPE_H264, pmt[12].toInt() and 0xFF)
        assertEquals(MpegTsMuxer.STREAM_TYPE_AAC_ADTS, pmt[17].toInt() and 0xFF)

        val video = packets.filter { it.pid == MpegTsMuxer.VIDEO_PID }
        assertTrue(video.first().payloadStart)
        assertTrue(video.drop(1).none { it.payloadStart })
        val firstBytes = video.first().bytes
        assertTrue(MpegTsMuxer.isPacket(firstBytes, 0))
        assertEquals(270_000L + MpegTsMuxer.PTS_DELAY_90K, MpegTsMuxer.videoPesPts(firstBytes, 0))
        assertNull(MpegTsMuxer.videoPesPts(packets[0].bytes, 0))
        assertFalse(MpegTsMuxer.isPacket(ByteArray(10), 0))

        val audio = packets.filter { it.pid == MpegTsMuxer.AUDIO_PID }
        assertTrue(audio.isNotEmpty())
        val audioPes = audio.fold(ByteArray(0)) { acc, packet -> acc + packet.payload }
        assertEquals(273_000L + MpegTsMuxer.PTS_DELAY_90K, MpegTsMuxer.decodeTimestamp(audioPes, 9))
        assertArrayEquals(byteArrayOf(0xFF.toByte(), 0xF1.toByte()), audioPes.copyOfRange(14, 16))
    }

    @Test
    fun deltaFrameAudioDisabledAndUnattachedOutputBehaveSafely() {
        val videoOnly = mux(hasAudio = false) {
            it.writeVideo(3_000, ByteArray(50) { 3 }, isKeyframe = false, videoConfig = byteArrayOf(0, 0, 0, 1, 0x67))
            it.writeAudio(3_000, ByteArray(50))
        }
        assertEquals(listOf(MpegTsMuxer.VIDEO_PID), videoOnly.map { it.pid })

        assertThrows(IllegalStateException::class.java) {
            MpegTsMuxer(hasAudio = false).writeTables()
        }
    }
}
