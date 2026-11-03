package com.amaia23.hydracam.spike.preview

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/** Minimal SNTP client: wall-clock offset (server - local) in ms, from the lowest-RTT sample. */
object Sntp {
    data class Result(val offsetMs: Double, val rttMs: Double, val server: String)

    fun query(host: String, samples: Int = 6): Result? {
        val address = runCatching { InetAddress.getByName(host) }.getOrNull() ?: return null
        var best: Result? = null
        DatagramSocket().use { socket ->
            socket.soTimeout = 1_500
            repeat(samples) {
                val request = ByteArray(48).apply { this[0] = 0x23 } // LI 0, VN 4, mode 3 (client)
                val t1 = System.currentTimeMillis()
                runCatching {
                    socket.send(DatagramPacket(request, request.size, address, 123))
                    val response = DatagramPacket(ByteArray(48), 48)
                    socket.receive(response)
                    val t4 = System.currentTimeMillis()
                    val t2 = ntpMs(response.data, 32)
                    val t3 = ntpMs(response.data, 40)
                    val rtt = (t4 - t1) - (t3 - t2)
                    val offset = ((t2 - t1) + (t3 - t4)) / 2.0
                    if (best == null || rtt < best!!.rttMs) best = Result(offset, rtt, address.hostAddress ?: host)
                }
            }
        }
        return best
    }

    private fun ntpMs(b: ByteArray, at: Int): Double {
        var seconds = 0L
        var fraction = 0L
        for (i in 0 until 4) seconds = (seconds shl 8) or (b[at + i].toLong() and 0xff)
        for (i in 4 until 8) fraction = (fraction shl 8) or (b[at + i].toLong() and 0xff)
        return (seconds - 2_208_988_800L) * 1_000.0 + fraction * 1_000.0 / 4_294_967_296.0
    }
}
