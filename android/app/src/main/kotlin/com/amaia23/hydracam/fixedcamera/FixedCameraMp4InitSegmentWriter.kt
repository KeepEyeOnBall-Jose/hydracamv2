package com.amaia23.hydracam.fixedcamera

import java.io.ByteArrayOutputStream
import java.io.File

object FixedCameraMp4InitSegmentWriter {
    fun write(
        file: File,
        width: Int,
        height: Int,
        avcConfig: ByteArray,
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
    ) {
        val includeAudio = channelCount > 0
        file.parentFile?.mkdirs()
        file.writeBytes(
            concat(
                box("ftyp", ftyp(includeAudio)),
                box(
                    "moov",
                    moov(
                        width = width,
                        height = height,
                        avcConfig = avcConfig,
                        sampleRate = sampleRate,
                        channelCount = channelCount,
                        audioBitRate = audioBitRate,
                        includeAudio = includeAudio,
                    ),
                ),
            ),
        )
    }

    private fun ftyp(includeAudio: Boolean): ByteArray =
        bytes {
            writeAscii("iso6")
            writeUInt32(1)
            writeAscii("iso6")
            writeAscii("mp41")
            writeAscii("avc1")
            if (includeAudio) {
                writeAscii("mp4a")
            }
        }

    private fun moov(
        width: Int,
        height: Int,
        avcConfig: ByteArray,
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        includeAudio: Boolean,
    ): ByteArray {
        val children = mutableListOf(
            box("mvhd", mvhd()),
            box("trak", videoTrak(width, height, avcConfig)),
        )
        val trexChildren = mutableListOf(box("trex", trex(VIDEO_TRACK_ID)))
        if (includeAudio) {
            val audioSpecificConfig = audioSpecificConfig(sampleRate, channelCount)
            children += box("trak", audioTrak(sampleRate, channelCount, audioBitRate, audioSpecificConfig))
            trexChildren += box("trex", trex(AUDIO_TRACK_ID))
        }
        children += box("mvex", concat(*trexChildren.toTypedArray()))
        return concat(*children.toTypedArray())
    }

    private fun mvhd(): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(0)
            writeUInt32(0)
            writeUInt32(MOVIE_TIMESCALE)
            writeUInt32(0)
            writeUInt32(0x00010000)
            writeUInt16(0x0100)
            writeUInt16(0)
            repeat(2) { writeUInt32(0) }
            writeUnityMatrix()
            repeat(6) { writeUInt32(0) }
            writeUInt32(3)
        }

    private fun videoTrak(width: Int, height: Int, avcConfig: ByteArray): ByteArray =
        concat(
            box("tkhd", tkhd(trackId = VIDEO_TRACK_ID, width = width, height = height, volume = 0)),
            box("mdia", videoMdia(width, height, avcConfig)),
        )

    private fun audioTrak(
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        audioSpecificConfig: ByteArray,
    ): ByteArray =
        concat(
            box("tkhd", tkhd(trackId = AUDIO_TRACK_ID, width = 0, height = 0, volume = 0x0100)),
            box("mdia", audioMdia(sampleRate, channelCount, audioBitRate, audioSpecificConfig)),
        )

    private fun tkhd(trackId: Int, width: Int, height: Int, volume: Int): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0x000007)
            writeUInt32(0)
            writeUInt32(0)
            writeUInt32(trackId)
            writeUInt32(0)
            writeUInt32(0)
            repeat(2) { writeUInt32(0) }
            writeUInt16(0)
            writeUInt16(0)
            writeUInt16(volume)
            writeUInt16(0)
            writeUnityMatrix()
            writeUInt32(width.toLong() shl 16)
            writeUInt32(height.toLong() shl 16)
        }

    private fun videoMdia(width: Int, height: Int, avcConfig: ByteArray): ByteArray =
        concat(
            box("mdhd", mdhd(VIDEO_TIMESCALE)),
            box("hdlr", hdlr("vide", "VideoHandler")),
            box("minf", videoMinf(width, height, avcConfig)),
        )

    private fun audioMdia(
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        audioSpecificConfig: ByteArray,
    ): ByteArray =
        concat(
            box("mdhd", mdhd(sampleRate)),
            box("hdlr", hdlr("soun", "SoundHandler")),
            box("minf", audioMinf(sampleRate, channelCount, audioBitRate, audioSpecificConfig)),
        )

    private fun mdhd(timescale: Int): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(0)
            writeUInt32(0)
            writeUInt32(timescale)
            writeUInt32(0)
            writeUInt16(0x55C4)
            writeUInt16(0)
        }

    private fun hdlr(handlerType: String, name: String): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(0)
            writeAscii(handlerType)
            repeat(3) { writeUInt32(0) }
            writeAscii(name)
            writeUInt8(0)
        }

    private fun videoMinf(width: Int, height: Int, avcConfig: ByteArray): ByteArray =
        concat(
            box("vmhd", vmhd()),
            box("dinf", box("dref", dref())),
            box("stbl", videoStbl(width, height, avcConfig)),
        )

    private fun audioMinf(
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        audioSpecificConfig: ByteArray,
    ): ByteArray =
        concat(
            box("smhd", smhd()),
            box("dinf", box("dref", dref())),
            box("stbl", audioStbl(sampleRate, channelCount, audioBitRate, audioSpecificConfig)),
        )

    private fun vmhd(): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0x000001)
            writeUInt16(0)
            repeat(3) { writeUInt16(0) }
        }

    private fun smhd(): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt16(0)
            writeUInt16(0)
        }

    private fun dref(): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(1)
            write(box("url ", bytes { writeFullBoxHeader(version = 0, flags = 0x000001) }))
        }

    private fun videoStbl(width: Int, height: Int, avcConfig: ByteArray): ByteArray =
        concat(
            box("stsd", videoStsd(width, height, avcConfig)),
            box("stts", emptySampleTable()),
            box("stsc", emptySampleTable()),
            box("stsz", stsz()),
            box("stco", emptySampleTable()),
        )

    private fun audioStbl(
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        audioSpecificConfig: ByteArray,
    ): ByteArray =
        concat(
            box("stsd", audioStsd(sampleRate, channelCount, audioBitRate, audioSpecificConfig)),
            box("stts", emptySampleTable()),
            box("stsc", emptySampleTable()),
            box("stsz", stsz()),
            box("stco", emptySampleTable()),
        )

    private fun videoStsd(width: Int, height: Int, avcConfig: ByteArray): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(1)
            write(box("avc1", avc1(width, height, avcConfig)))
        }

    private fun audioStsd(
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        audioSpecificConfig: ByteArray,
    ): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(1)
            write(box("mp4a", mp4a(sampleRate, channelCount, audioBitRate, audioSpecificConfig)))
        }

    private fun avc1(width: Int, height: Int, avcConfig: ByteArray): ByteArray =
        bytes {
            repeat(6) { writeUInt8(0) }
            writeUInt16(1)
            writeUInt16(0)
            writeUInt16(0)
            repeat(3) { writeUInt32(0) }
            writeUInt16(width)
            writeUInt16(height)
            writeUInt32(0x00480000)
            writeUInt32(0x00480000)
            writeUInt32(0)
            writeUInt16(1)
            writeCompressorName("HydraCam AVC")
            writeUInt16(0x0018)
            writeUInt16(0xFFFF)
            write(box("avcC", avcConfig))
        }

    private fun mp4a(
        sampleRate: Int,
        channelCount: Int,
        audioBitRate: Int,
        audioSpecificConfig: ByteArray,
    ): ByteArray =
        bytes {
            repeat(6) { writeUInt8(0) }
            writeUInt16(1)
            repeat(2) { writeUInt32(0) }
            writeUInt16(channelCount)
            writeUInt16(16)
            writeUInt16(0)
            writeUInt16(0)
            writeUInt32(sampleRate.toLong() shl 16)
            write(box("esds", esds(audioBitRate, audioSpecificConfig)))
        }

    private fun esds(audioBitRate: Int, audioSpecificConfig: ByteArray): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            val decoderSpecificInfo = descriptor(tag = 0x05, payload = audioSpecificConfig)
            val decoderConfig = descriptor(
                tag = 0x04,
                payload = bytes {
                    writeUInt8(0x40)
                    writeUInt8(0x15)
                    writeUInt24(0)
                    writeUInt32(audioBitRate)
                    writeUInt32(audioBitRate)
                    write(decoderSpecificInfo)
                },
            )
            val slConfig = descriptor(tag = 0x06, payload = byteArrayOf(0x02))
            write(
                descriptor(
                    tag = 0x03,
                    payload = bytes {
                        writeUInt16(1)
                        writeUInt8(0)
                        write(decoderConfig)
                        write(slConfig)
                    },
                ),
            )
        }

    private fun descriptor(tag: Int, payload: ByteArray): ByteArray =
        bytes {
            writeUInt8(tag)
            writeDescriptorLength(payload.size)
            write(payload)
        }

    private fun audioSpecificConfig(sampleRate: Int, channelCount: Int): ByteArray {
        val sampleRateIndex = when (sampleRate) {
            96_000 -> 0
            88_200 -> 1
            64_000 -> 2
            48_000 -> 3
            44_100 -> 4
            32_000 -> 5
            24_000 -> 6
            22_050 -> 7
            16_000 -> 8
            12_000 -> 9
            11_025 -> 10
            8_000 -> 11
            7_350 -> 12
            else -> error("Unsupported AAC sample rate $sampleRate.")
        }
        val bits = (AAC_LC_OBJECT_TYPE shl 11) or (sampleRateIndex shl 7) or (channelCount shl 3)
        return byteArrayOf((bits ushr 8).toByte(), bits.toByte())
    }

    private fun emptySampleTable(): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(0)
        }

    private fun stsz(): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(0)
            writeUInt32(0)
        }

    private fun trex(trackId: Int): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(trackId)
            writeUInt32(1)
            writeUInt32(0)
            writeUInt32(0)
            writeUInt32(0)
        }

    private fun box(type: String, payload: ByteArray): ByteArray =
        bytes {
            writeUInt32(payload.size + BOX_HEADER_BYTES)
            writeAscii(type)
            write(payload)
        }

    private fun concat(vararg parts: ByteArray): ByteArray =
        bytes {
            parts.forEach(::write)
        }

    private fun bytes(block: ByteArrayOutputStream.() -> Unit): ByteArray =
        ByteArrayOutputStream().apply(block).toByteArray()

    private fun ByteArrayOutputStream.writeFullBoxHeader(version: Int, flags: Int) {
        writeUInt8(version)
        writeUInt24(flags)
    }

    private fun ByteArrayOutputStream.writeUnityMatrix() {
        writeUInt32(0x00010000)
        writeUInt32(0)
        writeUInt32(0)
        writeUInt32(0)
        writeUInt32(0x00010000)
        writeUInt32(0)
        writeUInt32(0)
        writeUInt32(0)
        writeUInt32(0x40000000)
    }

    private fun ByteArrayOutputStream.writeCompressorName(name: String) {
        val bytes = name.toByteArray(Charsets.US_ASCII).take(31)
        writeUInt8(bytes.size)
        bytes.forEach { writeUInt8(it.toInt()) }
        repeat(31 - bytes.size) { writeUInt8(0) }
    }

    private fun ByteArrayOutputStream.writeAscii(value: String) {
        write(value.toByteArray(Charsets.US_ASCII))
    }

    private fun ByteArrayOutputStream.writeDescriptorLength(value: Int) {
        writeUInt8(0x80 or ((value ushr 21) and 0x7F))
        writeUInt8(0x80 or ((value ushr 14) and 0x7F))
        writeUInt8(0x80 or ((value ushr 7) and 0x7F))
        writeUInt8(value and 0x7F)
    }

    private fun ByteArrayOutputStream.writeUInt8(value: Int) {
        write(value and 0xFF)
    }

    private fun ByteArrayOutputStream.writeUInt16(value: Int) {
        writeUInt8(value ushr 8)
        writeUInt8(value)
    }

    private fun ByteArrayOutputStream.writeUInt24(value: Int) {
        writeUInt8(value ushr 16)
        writeUInt8(value ushr 8)
        writeUInt8(value)
    }

    private fun ByteArrayOutputStream.writeUInt32(value: Int) {
        writeUInt32(value.toLong())
    }

    private fun ByteArrayOutputStream.writeUInt32(value: Long) {
        writeUInt8((value ushr 24).toInt())
        writeUInt8((value ushr 16).toInt())
        writeUInt8((value ushr 8).toInt())
        writeUInt8(value.toInt())
    }

    private const val BOX_HEADER_BYTES = 8
    private const val MOVIE_TIMESCALE = 1_000
    private const val VIDEO_TIMESCALE = 90_000
    private const val VIDEO_TRACK_ID = 1
    private const val AUDIO_TRACK_ID = 2
    private const val AAC_LC_OBJECT_TYPE = 2
}
