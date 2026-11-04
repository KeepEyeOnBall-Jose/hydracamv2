package com.amaia23.hydracam.court

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Bundle
import android.view.Surface

/**
 * H8/S1: the dedicated 640x360 H.264 preview encoder (never the proxy). Its input [surface] joins
 * the capture session once; the recorder's repeating burst decides how many camera frames reach
 * it. Output goes to [onConfig] / [onFrame] from the drain thread; they must not block.
 *
 * Settings from the H8 spike: CBR when offered (else VBR), Baseline 3.1 (every WHEP browser, no
 * B-frames), 1 s GOP, realtime priority; a plain format if the encoder refuses those.
 */
class CourtPreviewEncoder private constructor(
    private val codec: MediaCodec,
    val surface: Surface,
    private val onConfig: (PreviewCodecConfig) -> Unit,
    private val onFrame: (PreviewFrame) -> Unit,
    private val logger: CourtLogger,
) : PreviewEncoderControl {
    @Volatile
    private var running = true
    private val info = MediaCodec.BufferInfo()
    private val drainThread = Thread({ drain() }, "CourtPreviewEncoder")

    private fun start() {
        codec.start()
        drainThread.start()
    }

    override fun requestKeyFrame() {
        setParameter(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
    }

    override fun setBitrateKbps(kbps: Int) {
        setParameter(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, kbps * BPS_PER_KBPS)
    }

    fun release() {
        running = false
        drainThread.join(RELEASE_JOIN_MS)
        runCatching { codec.stop() }
        codec.release()
        surface.release()
    }

    private fun setParameter(key: String, value: Int) {
        try {
            codec.setParameters(Bundle().apply { putInt(key, value) })
        } catch (error: IllegalStateException) {
            logger.warn(TAG, "Preview encoder rejected $key.", error)
        }
    }

    private fun drain() {
        while (running) {
            val index = try {
                codec.dequeueOutputBuffer(info, DRAIN_TIMEOUT_US)
            } catch (ignored: IllegalStateException) {
                // Released under us: the service is stopping.
                return
            }
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                configOf(codec.outputFormat)?.let(onConfig)
            } else if (index >= 0) {
                emit(index)
            }
        }
    }

    private fun emit(index: Int) {
        val buffer = codec.getOutputBuffer(index)
        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
        if (buffer != null && info.size > 0 && !isConfig) {
            val bytes = ByteArray(info.size)
            buffer.position(info.offset)
            buffer.limit(info.offset + info.size)
            buffer.get(bytes)
            onFrame(PreviewFrame(bytes, info.presentationTimeUs, info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0))
        }
        codec.releaseOutputBuffer(index, false)
    }

    companion object {
        private const val TAG = "CourtPreview"
        private const val WIDTH = 640
        private const val HEIGHT = 360
        private const val START_KBPS = 900
        private const val BPS_PER_KBPS = 1_000
        private const val GOP_S = 1
        private const val REALTIME_PRIORITY = 0
        private const val DRAIN_TIMEOUT_US = 10_000L
        private const val RELEASE_JOIN_MS = 1_000L

        /** Null when this phone has no usable AVC surface encoder at 640x360 (preview then nacks). */
        fun createOrNull(
            onConfig: (PreviewCodecConfig) -> Unit,
            onFrame: (PreviewFrame) -> Unit,
            logger: CourtLogger,
        ): CourtPreviewEncoder? {
            val codec = try {
                MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            } catch (error: Exception) {
                logger.warn(TAG, "No AVC encoder for the preview.", error)
                return null
            }
            val encoder = formats(codec).firstNotNullOfOrNull { (name, format) ->
                try {
                    codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    val surface = codec.createInputSurface()
                    logger.info(
                        TAG,
                        "Preview encoder ${codec.name} ${WIDTH}x$HEIGHT@${PreviewRateGovernor.MAX_FPS} ($name).",
                    )
                    CourtPreviewEncoder(codec, surface, onConfig, onFrame, logger).also { it.start() }
                } catch (error: Exception) {
                    logger.warn(TAG, "Preview encoder refused $name.", error)
                    codec.reset()
                    null
                }
            }
            if (encoder == null) {
                codec.release()
            }
            return encoder
        }

        private fun formats(codec: MediaCodec): List<Pair<String, MediaFormat>> {
            val cbr = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .firstOrNull { it.name == codec.name }
                ?.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                ?.encoderCapabilities
                ?.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR) == true
            val mode = if (cbr) "cbr" else "vbr"
            val tuned = base().apply {
                setInteger(
                    MediaFormat.KEY_BITRATE_MODE,
                    if (cbr) {
                        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
                    } else {
                        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
                    },
                )
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel31)
            }
            return listOf("$mode+baseline" to tuned, "default" to base())
        }

        private fun base(): MediaFormat =
            MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, WIDTH, HEIGHT).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, START_KBPS * BPS_PER_KBPS)
                setInteger(MediaFormat.KEY_FRAME_RATE, PreviewRateGovernor.MAX_FPS)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, GOP_S)
                setInteger(MediaFormat.KEY_PRIORITY, REALTIME_PRIORITY)
            }

        /** csd-0 / csd-1 are the SPS and PPS (Annex B). */
        private fun configOf(format: MediaFormat): PreviewCodecConfig? {
            val sps = format.getByteBuffer("csd-0")?.let(::copyOf) ?: return null
            val pps = format.getByteBuffer("csd-1")?.let(::copyOf) ?: return null
            return PreviewCodecConfig(sps, pps)
        }

        private fun copyOf(buffer: java.nio.ByteBuffer): ByteArray {
            val copy = buffer.duplicate()
            return ByteArray(copy.remaining()).also { copy.get(it) }
        }
    }
}
