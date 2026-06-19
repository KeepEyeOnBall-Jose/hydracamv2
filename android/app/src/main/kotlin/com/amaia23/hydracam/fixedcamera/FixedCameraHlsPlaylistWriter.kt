package com.amaia23.hydracam.fixedcamera

import java.io.File
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max

object FixedCameraHlsPlaylistWriter {
    data class Segment(
        val fileName: String,
        val durationSeconds: Double,
    )

    fun chunkFileName(deviceId: String, recordingId: String, chunkNumber: Int): String =
        "%s-%s-%08d.m4s".format(Locale.US, deviceId, recordingId, chunkNumber)

    fun write(
        file: File,
        initFileName: String,
        segments: List<Segment>,
        isFinal: Boolean,
    ) {
        file.parentFile?.mkdirs()
        file.writeText(render(initFileName, segments, isFinal))
    }

    fun render(
        initFileName: String,
        segments: List<Segment>,
        isFinal: Boolean,
    ): String {
        val targetDuration = max(
            1,
            ceil(segments.maxOfOrNull { it.durationSeconds } ?: 1.0).toInt(),
        )
        return buildString {
            appendLine("#EXTM3U")
            appendLine("#EXT-X-VERSION:7")
            appendLine("#EXT-X-TARGETDURATION:$targetDuration")
            appendLine("#EXT-X-MEDIA-SEQUENCE:0")
            appendLine("#EXT-X-INDEPENDENT-SEGMENTS")
            appendLine("#EXT-X-MAP:URI=\"$initFileName\"")
            segments.forEach { segment ->
                appendLine("#EXTINF:${"%.3f".format(Locale.US, segment.durationSeconds)},")
                appendLine(segment.fileName)
            }
            if (isFinal) {
                appendLine("#EXT-X-ENDLIST")
            }
        }
    }
}
