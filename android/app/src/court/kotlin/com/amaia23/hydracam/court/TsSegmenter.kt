package com.amaia23.hydracam.court

import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.DigestOutputStream
import java.security.MessageDigest

/** One closed segment file (`sessions/<sid>/<tier>/<seq>.ts`). */
data class SegmentRecord(
    val sessionId: String,
    val slot: String,
    val tier: String,
    val seq: Long,
    val file: File,
    val bytes: Long,
    val sha256: String,
    val mediaStartServerMs: Long,
    val durationMs: Long,
    val frames: Int,
    val offsetMs: Long,
    val rttMs: Long,
) {
    /** `segments.jsonl` line. H10: the clock offset in use is logged per segment. */
    fun toSidecarJson(closedAtMs: Long): JSONObject =
        JSONObject()
            .put("sessionId", sessionId)
            .put("slot", slot)
            .put("tier", tier)
            .put("seq", seq)
            .put("file", "$tier/${file.name}")
            .put("bytes", bytes)
            .put("sha256", sha256)
            .put("mediaStartServerMs", mediaStartServerMs)
            .put("durationMs", durationMs)
            .put("frames", frames)
            .put("offsetMs", offsetMs)
            .put("rttMs", rttMs)
            .put("closedAtMs", closedAtMs)
}

/** C1 `seq` starts at 0 per (session, slot, tier) and survives restarts. −1 = none written. */
interface SegmentSeqStore {
    fun lastSeq(sessionId: String, tier: String): Long

    fun commitSeq(sessionId: String, tier: String, seq: Long)
}

class InMemorySegmentSeqStore : SegmentSeqStore {
    private val values = mutableMapOf<String, Long>()

    @Synchronized
    override fun lastSeq(sessionId: String, tier: String): Long = values["$sessionId/$tier"] ?: -1

    @Synchronized
    override fun commitSeq(sessionId: String, tier: String, seq: Long) {
        values["$sessionId/$tier"] = seq
    }
}

/** Court files live under `<root>/sessions/<sid>/`. */
class CourtStorage(val root: File) {
    fun sessionDir(sessionId: String): File = File(File(root, "sessions"), safeName(sessionId))

    fun tierDir(sessionId: String, tier: String): File = File(sessionDir(sessionId), tier)

    fun sidecar(sessionId: String): File = File(sessionDir(sessionId), "segments.jsonl")

    fun signalsLog(): File = File(root, "signals.jsonl")

    private fun safeName(value: String): String = value.replace(Regex("[^A-Za-z0-9._-]"), "_")
}

/** Append-only JSONL file, fsynced per line. Shared by both tiers of a session. */
class JsonlAppender(private val file: File) {
    @Synchronized
    fun append(json: JSONObject) {
        file.parentFile?.mkdirs()
        FileOutputStream(file, true).use { stream ->
            stream.write((json.toString() + "\n").toByteArray(Charsets.UTF_8))
            stream.fd.sync()
        }
    }
}

/**
 * Shared presentation-time origin for both tiers of one session, so `seq` N of proxy and master
 * cover the same media time. [toServerMs] maps an encoder pts (µs) to K2 server time.
 */
class SessionTimebase(private val toServerMs: (ptsUs: Long) -> Long) {
    @get:Synchronized
    var baseUs: Long = -1
        private set

    @Synchronized
    fun anchor(ptsUs: Long): Long {
        if (baseUs < 0) {
            baseUs = ptsUs
        }
        return baseUs
    }

    fun relative90k(ptsUs: Long): Long = MpegTsMuxer.usTo90k(ptsUs - anchor(ptsUs))

    fun serverMs(ptsUs: Long): Long = toServerMs(ptsUs)
}

/**
 * H6: cuts one tier's H.264 (+ optional AAC) stream into ~[segmentDurationUs] MPEG-TS files.
 *
 * - Frames before the first IDR are dropped; each segment starts on an IDR.
 * - A segment closes at the first IDR at or after `segmentDurationUs − ½ frame`. [requestSyncFrame]
 *   is called once per segment when that point is near, so the encoder delivers the IDR on time.
 * - Files are written as `<seq>.ts.part`, fsynced, then renamed; `seq` is committed only on close.
 *
 * Thread-safe: the video drain and audio threads call in concurrently.
 */
class TsSegmenter(
    private val sessionId: String,
    private val slot: String,
    private val tier: String,
    private val directory: File,
    private val sidecar: JsonlAppender,
    private val seqStore: SegmentSeqStore,
    private val timebase: SessionTimebase,
    private val segmentDurationUs: Long,
    private val frameDurationUs: Long,
    private val hasAudio: Boolean,
    private val clockEstimate: () -> ClockEstimate?,
    private val onSegment: (SegmentRecord) -> Unit,
    private val requestSyncFrame: () -> Unit = {},
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val logger: CourtLogger = NoopCourtLogger,
) {
    private var videoConfig: ByteArray? = null
    private var current: OpenSegment? = null
    private var syncRequested = false
    private var closed = false

    @get:Synchronized
    var lastSeq: Long = seqStore.lastSeq(sessionId, tier)
        private set

    init {
        directory.mkdirs()
        directory.listFiles { file -> file.name.endsWith(PART_SUFFIX) }?.forEach { part ->
            logger.warn(TAG, "Dropping unfinished ${part.name} for $sessionId/$tier.")
            part.delete()
        }
    }

    /** SPS/PPS from the encoder's `BUFFER_FLAG_CODEC_CONFIG` output (Annex-B). */
    @Synchronized
    fun onVideoConfig(config: ByteArray) {
        videoConfig = config
    }

    @Synchronized
    @Throws(IOException::class)
    fun onVideoFrame(ptsUs: Long, annexB: ByteArray, isKeyframe: Boolean) {
        if (closed) {
            return
        }
        val open = current
        if (open == null) {
            if (!isKeyframe) {
                return
            }
            current = openSegment(ptsUs)
        } else {
            val elapsedUs = ptsUs - open.startPtsUs
            if (isKeyframe && elapsedUs >= segmentDurationUs - frameDurationUs / 2) {
                closeSegment(open, endPtsUs = ptsUs)
                current = openSegment(ptsUs)
            } else if (!syncRequested && elapsedUs >= segmentDurationUs - 2 * frameDurationUs) {
                syncRequested = true
                requestSyncFrame()
            }
        }
        val segment = current ?: return
        segment.muxer.writeVideo(timebase.relative90k(ptsUs), annexB, isKeyframe, videoConfig)
        segment.frames += 1
        segment.lastPtsUs = ptsUs
    }

    /** Raw AAC frames; dropped until the first video segment opens. */
    @Synchronized
    @Throws(IOException::class)
    fun onAudioFrame(ptsUs: Long, aacRaw: ByteArray) {
        val segment = current ?: return
        if (closed || !hasAudio || ptsUs < timebase.baseUs) {
            return
        }
        segment.muxer.writeAudio(timebase.relative90k(ptsUs), aacRaw)
    }

    /** Close the open segment (if any). Returns the tier's last committed seq (−1 = none). */
    @Synchronized
    @Throws(IOException::class)
    fun finish(): Long {
        if (!closed) {
            closed = true
            current?.let { closeSegment(it, endPtsUs = it.lastPtsUs + frameDurationUs) }
            current = null
        }
        return lastSeq
    }

    /** Drop the open segment without committing it (encoder failure). */
    @Synchronized
    fun abort() {
        closed = true
        current?.let { open ->
            runCatching { open.stream.close() }
            open.partFile.delete()
        }
        current = null
    }

    private fun openSegment(startPtsUs: Long): OpenSegment {
        val seq = lastSeq + 1
        val partFile = File(directory, "%06d.ts%s".format(seq, PART_SUFFIX))
        val fileStream = FileOutputStream(partFile)
        val digest = MessageDigest.getInstance("SHA-256")
        val stream = BufferedOutputStream(DigestOutputStream(fileStream, digest), BUFFER_BYTES)
        val muxer = MpegTsMuxer(hasAudio)
        muxer.attach(stream)
        syncRequested = false
        timebase.anchor(startPtsUs)
        return OpenSegment(seq, startPtsUs, partFile, fileStream, stream, digest, muxer)
    }

    private fun closeSegment(open: OpenSegment, endPtsUs: Long) {
        open.stream.flush()
        open.fileStream.fd.sync()
        open.stream.close()
        val finalFile = File(directory, "%06d.ts".format(open.seq))
        if (!open.partFile.renameTo(finalFile)) {
            throw IOException("Could not rename ${open.partFile.name}.")
        }
        val estimate = clockEstimate()
        val record = SegmentRecord(
            sessionId = sessionId,
            slot = slot,
            tier = tier,
            seq = open.seq,
            file = finalFile,
            bytes = finalFile.length(),
            sha256 = open.digest.digest().toHex(),
            mediaStartServerMs = timebase.serverMs(open.startPtsUs),
            durationMs = (endPtsUs - open.startPtsUs) / 1_000,
            frames = open.frames,
            offsetMs = estimate?.offsetMs ?: 0,
            rttMs = estimate?.rttMs ?: -1,
        )
        sidecar.append(record.toSidecarJson(clock.nowMs()))
        seqStore.commitSeq(sessionId, tier, open.seq)
        lastSeq = open.seq
        logger.info(TAG, "Closed $sessionId/$tier seq=${open.seq} ${record.bytes} B ${record.durationMs} ms.")
        onSegment(record)
    }

    private class OpenSegment(
        val seq: Long,
        val startPtsUs: Long,
        val partFile: File,
        val fileStream: FileOutputStream,
        val stream: BufferedOutputStream,
        val digest: MessageDigest,
        val muxer: MpegTsMuxer,
    ) {
        var frames = 0
        var lastPtsUs = startPtsUs
    }

    companion object {
        const val PART_SUFFIX = ".part"
        private const val BUFFER_BYTES = 256 * 1024
        private const val TAG = "CourtSegmenter"
    }
}

internal fun ByteArray.toHex(): String {
    val chars = CharArray(size * 2)
    forEachIndexed { index, byte ->
        val value = byte.toInt() and 0xFF
        chars[index * 2] = HEX[value ushr 4]
        chars[index * 2 + 1] = HEX[value and 0x0F]
    }
    return String(chars)
}

private val HEX = "0123456789abcdef".toCharArray()
