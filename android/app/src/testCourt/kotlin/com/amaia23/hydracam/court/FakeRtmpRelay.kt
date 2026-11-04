package com.amaia23.hydracam.court

import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * A loopback RTMP publish endpoint, just enough of MediaMTX for one publisher: the plain
 * handshake, chunk parsing (fmt 0–3, set chunk size, extended timestamps) and AMF0 replies to
 * `connect`, `createStream` and `publish`. It records what a relay would see.
 */
class FakeRtmpRelay(private val publishCode: String = "NetStream.Publish.Start") : Closeable {
    private val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
    private val thread = Thread(::serve, "FakeRtmpRelay").apply { isDaemon = true }
    private val closedLatch = CountDownLatch(1)

    val port: Int get() = server.localPort

    @Volatile var app: String? = null
        private set

    @Volatile var tcUrl: String? = null
        private set

    @Volatile var streamName: String? = null
        private set

    val commands = CopyOnWriteArrayList<String>()

    /** FLV video tag bodies, in arrival order. */
    val video = CopyOnWriteArrayList<ByteArray>()

    init {
        thread.start()
    }

    fun awaitVideo(count: Int, timeoutMs: Long = TIMEOUT_MS): Boolean = poll(timeoutMs) { video.size >= count }

    fun awaitClosed(timeoutMs: Long = TIMEOUT_MS): Boolean = closedLatch.await(timeoutMs, TimeUnit.MILLISECONDS)

    override fun close() {
        server.close()
    }

    private fun serve() {
        try {
            server.accept().use { socket ->
                session(socket)
            }
        } catch (ignored: IOException) {
            // closed
        } finally {
            closedLatch.countDown()
        }
    }

    private fun session(socket: Socket) {
        socket.soTimeout = TIMEOUT_MS.toInt()
        val input = DataInputStream(socket.getInputStream())
        val output = socket.getOutputStream()
        handshake(input, output)
        val reader = ChunkReader(input)
        val writer = ChunkWriter(output)
        writer.control(TYPE_SET_CHUNK_SIZE, int32(OUT_CHUNK_SIZE))
        writer.chunkSize = OUT_CHUNK_SIZE
        while (true) {
            val message = reader.next() ?: return
            when (message.type) {
                TYPE_VIDEO -> video += message.payload
                TYPE_COMMAND -> command(Amf0.decodeAll(message.payload), writer)
                else -> Unit
            }
        }
    }

    private fun command(values: List<Any?>, writer: ChunkWriter) {
        val name = values.getOrNull(0) as? String ?: return
        val txn = values.getOrNull(1) as? Double ?: 0.0
        commands += name
        when (name) {
            "connect" -> {
                @Suppress("UNCHECKED_CAST")
                val props = values.getOrNull(2) as? Map<String, Any?>
                app = props?.get("app") as? String
                tcUrl = props?.get("tcUrl") as? String
                writer.control(TYPE_WINDOW_ACK, int32(WINDOW))
                writer.control(TYPE_PEER_BANDWIDTH, int32(WINDOW) + byteArrayOf(2))
                writer.command(
                    0,
                    "_result",
                    txn,
                    mapOf("fmsVer" to "FMS/3,0,1,123", "capabilities" to 31.0),
                    mapOf(
                        "level" to "status",
                        "code" to "NetConnection.Connect.Success",
                        "description" to "Connection succeeded.",
                        "objectEncoding" to 0.0,
                    ),
                )
            }
            "createStream" -> writer.command(0, "_result", txn, null, STREAM_ID.toDouble())
            "publish" -> {
                streamName = values.getOrNull(3) as? String
                writer.command(
                    STREAM_ID,
                    "onStatus",
                    0.0,
                    null,
                    mapOf("level" to "status", "code" to publishCode, "description" to "publish"),
                )
            }
            else -> Unit
        }
    }

    private fun handshake(input: DataInputStream, output: OutputStream) {
        val c0 = input.readUnsignedByte()
        check(c0 == RTMP_VERSION) { "bad C0 $c0" }
        val c1 = ByteArray(HANDSHAKE_SIZE).also(input::readFully)
        output.write(RTMP_VERSION)
        output.write(ByteArray(HANDSHAKE_SIZE))
        output.write(c1)
        output.flush()
        input.readFully(ByteArray(HANDSHAKE_SIZE))
    }

    class Message(val type: Int, val streamId: Int, val payload: ByteArray)

    private class ChunkReader(private val input: DataInputStream) {
        private class Stream {
            var length = 0
            var type = 0
            var streamId = 0
            var extended = false
            val buffer = ByteArrayOutputStream()
        }

        private val streams = HashMap<Int, Stream>()
        private var chunkSize = DEFAULT_CHUNK_SIZE

        fun next(): Message? {
            while (true) {
                val first = readOrNull(input) ?: return null
                val fmt = first shr FMT_SHIFT
                val csid = when (val low = first and CSID_MASK) {
                    0 -> FIRST_EXTENDED_CSID + input.readUnsignedByte()
                    1 -> FIRST_EXTENDED_CSID + input.readUnsignedByte() + input.readUnsignedByte() * BYTE
                    else -> low
                }
                val stream = streams.getOrPut(csid, ::Stream)
                var timestamp = 0
                if (fmt <= FMT_TIMESTAMP_ONLY) {
                    timestamp = uint24(input)
                }
                if (fmt <= FMT_NO_STREAM_ID) {
                    stream.length = uint24(input)
                    stream.type = input.readUnsignedByte()
                }
                if (fmt == FMT_FULL) {
                    stream.streamId = Integer.reverseBytes(input.readInt())
                }
                if (fmt <= FMT_TIMESTAMP_ONLY) {
                    stream.extended = timestamp == EXTENDED_TIMESTAMP
                }
                if (stream.extended) {
                    input.readInt()
                }
                val remaining = stream.length - stream.buffer.size()
                val bytes = ByteArray(minOf(chunkSize, remaining)).also(input::readFully)
                stream.buffer.write(bytes)
                if (stream.buffer.size() >= stream.length) {
                    val message = Message(stream.type, stream.streamId, stream.buffer.toByteArray())
                    stream.buffer.reset()
                    if (message.type == TYPE_SET_CHUNK_SIZE) {
                        chunkSize = ByteBuffer.wrap(message.payload).int and Int.MAX_VALUE
                    } else {
                        return message
                    }
                }
            }
        }

        private fun readOrNull(input: InputStream): Int? {
            val b = try {
                input.read()
            } catch (ignored: IOException) {
                -1
            }
            return b.takeIf { it >= 0 }
        }
    }

    private class ChunkWriter(private val output: OutputStream) {
        var chunkSize = DEFAULT_CHUNK_SIZE

        fun control(type: Int, payload: ByteArray) = write(CSID_CONTROL, type, 0, payload)

        fun command(streamId: Int, vararg values: Any?) =
            write(CSID_COMMAND, TYPE_COMMAND, streamId, Amf0.encode(*values))

        private fun write(csid: Int, type: Int, streamId: Int, payload: ByteArray) {
            val out = ByteArrayOutputStream()
            out.write(csid)
            out.write(ByteArray(3))
            out.write(uint24Bytes(payload.size))
            out.write(type)
            out.write(ByteBuffer.allocate(4).putInt(Integer.reverseBytes(streamId)).array())
            var offset = 0
            while (offset < payload.size) {
                if (offset > 0) {
                    out.write((FMT_CONTINUATION shl FMT_SHIFT) or csid)
                }
                val n = minOf(chunkSize, payload.size - offset)
                out.write(payload, offset, n)
                offset += n
            }
            output.write(out.toByteArray())
            output.flush()
        }
    }

    /** The AMF0 subset RTMP commands use. */
    object Amf0 {
        fun decodeAll(bytes: ByteArray): List<Any?> {
            val buffer = ByteBuffer.wrap(bytes)
            val out = mutableListOf<Any?>()
            while (buffer.hasRemaining()) {
                out += value(buffer)
            }
            return out
        }

        fun encode(vararg values: Any?): ByteArray {
            val out = ByteArrayOutputStream()
            values.forEach { write(out, it) }
            return out.toByteArray()
        }

        private fun value(buffer: ByteBuffer): Any? = when (val marker = buffer.get().toInt()) {
            NUMBER -> buffer.double
            BOOLEAN -> buffer.get().toInt() != 0
            STRING -> string(buffer)
            OBJECT -> properties(buffer)
            NULL, UNDEFINED -> null
            ECMA_ARRAY -> {
                buffer.int
                properties(buffer)
            }
            else -> throw EOFException("unsupported AMF0 marker $marker")
        }

        private fun properties(buffer: ByteBuffer): Map<String, Any?> {
            val map = LinkedHashMap<String, Any?>()
            while (true) {
                val key = string(buffer)
                if (key.isEmpty() && buffer.get(buffer.position()).toInt() == OBJECT_END) {
                    buffer.get()
                    return map
                }
                map[key] = value(buffer)
            }
        }

        private fun string(buffer: ByteBuffer): String {
            val bytes = ByteArray(buffer.short.toInt() and SHORT_MASK)
            buffer.get(bytes)
            return String(bytes, Charsets.UTF_8)
        }

        private fun write(out: ByteArrayOutputStream, value: Any?) {
            when (value) {
                null -> out.write(NULL)
                is Double -> {
                    out.write(NUMBER)
                    out.write(ByteBuffer.allocate(8).putDouble(value).array())
                }
                is Boolean -> {
                    out.write(BOOLEAN)
                    out.write(if (value) 1 else 0)
                }
                is String -> {
                    out.write(STRING)
                    writeString(out, value)
                }
                is Map<*, *> -> {
                    out.write(OBJECT)
                    value.forEach { (k, v) ->
                        writeString(out, k as String)
                        write(out, v)
                    }
                    out.write(byteArrayOf(0, 0, OBJECT_END.toByte()))
                }
                else -> error("unsupported $value")
            }
        }

        private fun writeString(out: ByteArrayOutputStream, value: String) {
            val bytes = value.toByteArray(Charsets.UTF_8)
            out.write(ByteBuffer.allocate(2).putShort(bytes.size.toShort()).array())
            out.write(bytes)
        }

        private const val NUMBER = 0
        private const val BOOLEAN = 1
        private const val STRING = 2
        private const val OBJECT = 3
        private const val NULL = 5
        private const val UNDEFINED = 6
        private const val ECMA_ARRAY = 8
        private const val OBJECT_END = 9
        private const val SHORT_MASK = 0xFFFF
    }

    companion object {
        const val TIMEOUT_MS = 10_000L
        const val STREAM_ID = 1
        const val TYPE_VIDEO = 9
        private const val TYPE_SET_CHUNK_SIZE = 1
        private const val TYPE_WINDOW_ACK = 5
        private const val TYPE_PEER_BANDWIDTH = 6
        private const val TYPE_COMMAND = 20
        private const val RTMP_VERSION = 3
        private const val HANDSHAKE_SIZE = 1536
        private const val DEFAULT_CHUNK_SIZE = 128
        private const val OUT_CHUNK_SIZE = 4096
        private const val WINDOW = 2_500_000
        private const val CSID_CONTROL = 2
        private const val CSID_COMMAND = 3
        private const val FMT_SHIFT = 6
        private const val CSID_MASK = 0x3F
        private const val FIRST_EXTENDED_CSID = 64
        private const val BYTE = 256
        private const val FMT_FULL = 0
        private const val FMT_NO_STREAM_ID = 1
        private const val FMT_TIMESTAMP_ONLY = 2
        private const val FMT_CONTINUATION = 3
        private const val EXTENDED_TIMESTAMP = 0xFFFFFF

        private fun uint24(input: DataInputStream): Int =
            (input.readUnsignedByte() shl 16) or (input.readUnsignedByte() shl 8) or input.readUnsignedByte()

        private fun uint24Bytes(v: Int) = byteArrayOf((v shr 16).toByte(), (v shr 8).toByte(), v.toByte())

        private fun int32(v: Int): ByteArray = ByteBuffer.allocate(4).putInt(v).array()

        fun poll(timeoutMs: Long, condition: () -> Boolean): Boolean {
            val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (System.nanoTime() < deadline) {
                if (condition()) return true
                Thread.sleep(POLL_MS)
            }
            return condition()
        }

        private const val POLL_MS = 10L
    }
}
