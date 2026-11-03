package com.amaia23.hydracam.spike.preview

/**
 * A NAL unit carrying the capture wall-clock time, so a WHEP viewer can measure glass-to-glass
 * latency per frame. Body = 16-byte tag + ASCII "<wallMs>:<seq>" + 0x80; the tag has no zero
 * bytes, so no emulation-prevention bytes are ever needed.
 *
 * RootEncoder 2.8.1 drops every SEI NAL before muxing (NalReader.shouldKeepNal), so the default
 * carrier is a filler-data NAL (type 12), which decoders skip. SEI is kept for publishers that
 * pass it through.
 */
object CaptureTimeNal {
    enum class Carrier { FILLER, SEI }

    /** Shared with viewer/index.html. */
    val TAG = byteArrayOf(
        0x48, 0x38, 0x2d, 0x43, 0x41, 0x50, 0x54, 0x55, // "H8-CAPTU"
        0x52, 0x45, 0x2d, 0x54, 0x49, 0x4d, 0x45, 0x31, // "RE-TIME1"
    )

    fun nal(carrier: Carrier, captureWallMs: Long, seq: Long): ByteArray {
        val text = "$captureWallMs:$seq".toByteArray(Charsets.US_ASCII)
        val startCode = byteArrayOf(0, 0, 0, 1)
        val trailing = byteArrayOf(0x80.toByte())
        return when (carrier) {
            Carrier.FILLER -> startCode + byteArrayOf(0x0c) + TAG + text + trailing
            Carrier.SEI -> {
                // user_data_unregistered: payload type 5, one-byte size, UUID (= TAG), payload.
                val payloadSize = TAG.size + text.size
                check(payloadSize < 255)
                startCode + byteArrayOf(0x06, 0x05, payloadSize.toByte()) + TAG + text + trailing
            }
        }
    }
}
