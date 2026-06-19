package com.amaia23.hydracam.fixedcamera

import java.io.ByteArrayOutputStream
import java.io.File

object FixedCameraMp4FragmentWriter {
    data class TrackFragment(
        val trackId: Int,
        val baseMediaDecodeTime: Long,
        val samples: List<Sample>,
    )

    data class Sample(
        val duration: Int,
        val data: ByteArray,
        val flags: Int,
        val compositionTimeOffset: Int = 0,
    ) {
        companion object {
            fun video(
                duration: Int,
                data: ByteArray,
                isSyncSample: Boolean,
                compositionTimeOffset: Int = 0,
            ): Sample =
                Sample(
                    duration = duration,
                    data = data,
                    flags = if (isSyncSample) SAMPLE_FLAGS_SYNC else SAMPLE_FLAGS_NON_SYNC,
                    compositionTimeOffset = compositionTimeOffset,
                )

            fun audio(duration: Int, data: ByteArray): Sample =
                Sample(
                    duration = duration,
                    data = data,
                    flags = SAMPLE_FLAGS_SYNC,
                )

            private const val SAMPLE_FLAGS_SYNC = 0x02000000
            private const val SAMPLE_FLAGS_NON_SYNC = 0x01010000
        }
    }

    fun write(
        file: File,
        sequenceNumber: Long,
        fragments: List<TrackFragment>,
    ) {
        require(sequenceNumber in 0..UINT32_MAX) {
            "Fragment sequenceNumber must fit in uint32."
        }
        require(fragments.isNotEmpty()) {
            "Fragment must contain at least one track fragment."
        }
        fragments.forEach { fragment ->
            require(fragment.trackId > 0) {
                "Track id must be positive."
            }
            require(fragment.baseMediaDecodeTime >= 0) {
                "Base media decode time must be non-negative."
            }
            require(fragment.samples.isNotEmpty()) {
                "Track ${fragment.trackId} must contain at least one sample."
            }
            fragment.samples.forEach { sample ->
                require(sample.duration > 0) {
                    "Sample duration must be positive."
                }
                require(sample.data.isNotEmpty()) {
                    "Sample data must not be empty."
                }
            }
        }

        file.parentFile?.mkdirs()
        val stypBox = box("styp", styp())
        val mdatPayload = mediaData(fragments)
        val placeholderMoof = box(
            "moof",
            moof(
                sequenceNumber = sequenceNumber,
                fragments = fragments,
                dataOffsets = List(fragments.size) { 0 },
            ),
        )
        val dataOffsets = dataOffsets(
            moofSize = placeholderMoof.size,
            fragments = fragments,
        )
        val moofBox = box(
            "moof",
            moof(
                sequenceNumber = sequenceNumber,
                fragments = fragments,
                dataOffsets = dataOffsets,
            ),
        )
        file.writeBytes(
            concat(
                stypBox,
                moofBox,
                box("mdat", mdatPayload),
            ),
        )
    }

    private fun styp(): ByteArray =
        bytes {
            writeAscii("msdh")
            writeUInt32(0)
            writeAscii("msdh")
            writeAscii("msix")
            writeAscii("iso6")
            writeAscii("mp41")
        }

    private fun moof(
        sequenceNumber: Long,
        fragments: List<TrackFragment>,
        dataOffsets: List<Int>,
    ): ByteArray =
        concat(
            box("mfhd", mfhd(sequenceNumber)),
            *fragments.mapIndexed { index, fragment ->
                box("traf", traf(fragment, dataOffsets[index]))
            }.toTypedArray(),
        )

    private fun mfhd(sequenceNumber: Long): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = 0)
            writeUInt32(sequenceNumber)
        }

    private fun traf(fragment: TrackFragment, dataOffset: Int): ByteArray =
        concat(
            box("tfhd", tfhd(fragment.trackId)),
            box("tfdt", tfdt(fragment.baseMediaDecodeTime)),
            box("trun", trun(fragment.samples, dataOffset)),
        )

    private fun tfhd(trackId: Int): ByteArray =
        bytes {
            writeFullBoxHeader(version = 0, flags = TFHD_DEFAULT_BASE_IS_MOOF)
            writeUInt32(trackId)
        }

    private fun tfdt(baseMediaDecodeTime: Long): ByteArray =
        bytes {
            writeFullBoxHeader(version = 1, flags = 0)
            writeUInt64(baseMediaDecodeTime)
        }

    private fun trun(samples: List<Sample>, dataOffset: Int): ByteArray =
        bytes {
            writeFullBoxHeader(version = 1, flags = TRUN_FLAGS)
            writeUInt32(samples.size)
            writeUInt32(dataOffset)
            samples.forEach { sample ->
                writeUInt32(sample.duration)
                writeUInt32(sample.data.size)
                writeUInt32(sample.flags)
                writeInt32(sample.compositionTimeOffset)
            }
        }

    private fun dataOffsets(moofSize: Int, fragments: List<TrackFragment>): List<Int> {
        var mediaOffset = 0
        return fragments.map { fragment ->
            val offset = moofSize + BOX_HEADER_BYTES + mediaOffset
            mediaOffset += fragment.samples.sumOf { it.data.size }
            offset
        }
    }

    private fun mediaData(fragments: List<TrackFragment>): ByteArray =
        bytes {
            fragments.forEach { fragment ->
                fragment.samples.forEach { sample ->
                    write(sample.data)
                }
            }
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

    private fun ByteArrayOutputStream.writeAscii(value: String) {
        write(value.toByteArray(Charsets.US_ASCII))
    }

    private fun ByteArrayOutputStream.writeUInt8(value: Int) {
        write(value and 0xFF)
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

    private fun ByteArrayOutputStream.writeUInt64(value: Long) {
        writeUInt32(value ushr 32)
        writeUInt32(value)
    }

    private fun ByteArrayOutputStream.writeInt32(value: Int) {
        writeUInt32(value)
    }

    private const val BOX_HEADER_BYTES = 8
    private const val TFHD_DEFAULT_BASE_IS_MOOF = 0x020000
    private const val TRUN_DATA_OFFSET_PRESENT = 0x000001
    private const val TRUN_SAMPLE_DURATION_PRESENT = 0x000100
    private const val TRUN_SAMPLE_SIZE_PRESENT = 0x000200
    private const val TRUN_SAMPLE_FLAGS_PRESENT = 0x000400
    private const val TRUN_SAMPLE_COMPOSITION_TIME_OFFSET_PRESENT = 0x000800
    private const val TRUN_FLAGS = TRUN_DATA_OFFSET_PRESENT or
        TRUN_SAMPLE_DURATION_PRESENT or
        TRUN_SAMPLE_SIZE_PRESENT or
        TRUN_SAMPLE_FLAGS_PRESENT or
        TRUN_SAMPLE_COMPOSITION_TIME_OFFSET_PRESENT
    private const val UINT32_MAX = 0xFFFFFFFFL
}
