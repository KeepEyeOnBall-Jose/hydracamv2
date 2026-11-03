package com.amaia23.hydracam.court

import okio.ByteString.Companion.toByteString
import org.json.JSONException
import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.DigestOutputStream
import java.security.MessageDigest
import kotlin.math.abs

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
    fun toSidecarJson(closedAtMs: Long): JSONObject = JSONObject()
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
    /** [sessionId] comes from a validated C1 command; anything else is a programming error. */
    fun sessionDir(sessionId: String): File {
        require(CourtIds.isSafe(sessionId)) { "Unsafe session id." }
        return File(File(root, "sessions"), sessionId)
    }

    fun tierDir(sessionId: String, tier: String): File = File(sessionDir(sessionId), tier)

    fun sidecar(sessionId: String): File = File(sessionDir(sessionId), SegmentSidecarReader.SIDECAR)

    fun signalsLog(): File = File(root, "signals.jsonl")

    fun sessionDirs(): List<File> = File(root, "sessions").listFiles()?.filter { it.isDirectory }.orEmpty()
}

/**
 * Reads `segments.jsonl` back after a crash (the process died between the sidecar and queue writes).
 * Every field is validated; a line that names another session, a path outside its tier directory, or
 * a malformed hash is skipped.
 */
class SegmentSidecarReader(private val storage: CourtStorage, private val logger: CourtLogger) {
    fun readAll(): List<SegmentRecord> = storage.sessionDirs().flatMap(::read)

    private fun read(sessionDir: File): List<SegmentRecord> {
        val sidecar = File(sessionDir, SIDECAR)
        if (!sidecar.isFile) {
            return emptyList()
        }
        var skipped = 0
        val records = sidecar.readLines().mapNotNull { line ->
            parse(sessionDir, line).also { if (it == null && line.isNotBlank()) skipped += 1 }
        }
        if (skipped > 0) {
            logger.warn(TAG, "Skipped $skipped invalid line(s) in ${sessionDir.name}/$SIDECAR.")
        }
        return records
    }

    internal fun parse(sessionDir: File, line: String): SegmentRecord? {
        val json = try {
            JSONObject(line)
        } catch (ignored: JSONException) {
            null
        }
        val sessionId = json?.optString("sessionId")?.takeIf(CourtIds::isSafe) ?: return null
        val tier = json.optString("tier")
        val seq = json.optLong("seq", -1)
        val record = SegmentRecord(
            sessionId = sessionId,
            slot = json.optString("slot"),
            tier = tier,
            seq = seq,
            file = File(storage.tierDir(sessionId, tier), "%06d.ts".format(seq)),
            bytes = json.optLong("bytes", -1),
            sha256 = json.optString("sha256"),
            mediaStartServerMs = json.optLong("mediaStartServerMs", -1),
            durationMs = json.optLong("durationMs", -1),
            frames = json.optInt("frames"),
            offsetMs = json.optLong("offsetMs"),
            rttMs = json.optLong("rttMs", -1),
        )
        val valid = storage.sessionDir(sessionId) == sessionDir &&
            record.slot.isNotBlank() &&
            tier in C1.TIERS &&
            seq >= 0 &&
            json.optString("file") == "$tier/${record.file.name}" &&
            record.bytes > 0 &&
            SHA256.matches(record.sha256) &&
            record.mediaStartServerMs >= 0 &&
            record.durationMs >= 0
        return record.takeIf { valid }
    }

    companion object {
        const val SIDECAR = "segments.jsonl"
        private const val TAG = "CourtSidecar"
        private val SHA256 = Regex("[0-9a-f]{64}")
    }
}

/**
 * Append-only JSONL file, fsynced per line. Shared by both tiers of a session. A line torn by a
 * full disk is ended before the next append, so it costs only itself, never the next record.
 */
class JsonlAppender(private val file: File) {
    @Synchronized
    fun append(json: JSONObject) {
        file.absoluteFile.parentFile?.mkdirs()
        val line = (json.toString() + "\n").toByteArray(Charsets.UTF_8)
        val bytes = if (endsTorn()) byteArrayOf('\n'.code.toByte()) + line else line
        FileOutputStream(file, true).use { stream ->
            stream.write(bytes)
            stream.fd.sync()
        }
    }

    private fun endsTorn(): Boolean {
        if (!file.isFile || file.length() == 0L) {
            return false
        }
        return RandomAccessFile(file, "r").use { raf ->
            raf.seek(raf.length() - 1)
            raf.read() != '\n'.code
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

    private var baseServerMs = 0L

    @Synchronized
    fun anchor(ptsUs: Long): Long {
        if (baseUs < 0) {
            baseUs = ptsUs
            baseServerMs = toServerMs(ptsUs)
        }
        return baseUs
    }

    fun relative90k(ptsUs: Long): Long = MpegTsMuxer.usTo90k(ptsUs - anchor(ptsUs))

    /**
     * Live mapping until [anchor]; after it, the anchor's server time plus the pts delta, so a
     * wall-clock step or a new clock burst mid-session cannot open gaps or overlaps between segments.
     */
    @Synchronized
    fun serverMs(ptsUs: Long): Long =
        if (baseUs < 0) toServerMs(ptsUs) else baseServerMs + Math.floorDiv(ptsUs - baseUs, 1_000L)
}

/**
 * Encoder pts → device wall clock. Surface-input encoders carry the camera sensor timestamp, which is
 * `elapsedRealtimeNanos` (SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME) or, on some devices, `nanoTime`.
 * The first frame picks whichever clock it is closer to. [realtimeUs] is `elapsedRealtimeNanos / 1000`.
 */
internal class PtsClock(
    private var useRealtime: Boolean,
    private val realtimeUs: () -> Long,
    private val monotonicUs: () -> Long = { System.nanoTime() / 1_000 },
    private val wallMs: () -> Long = { System.currentTimeMillis() },
) {
    private var checked = false

    @Synchronized
    fun nowUs(): Long = if (useRealtime) realtimeUs() else monotonicUs()

    /** Returns true when the first frame switched the clock. */
    @Synchronized
    fun check(ptsUs: Long): Boolean {
        if (checked) {
            return false
        }
        checked = true
        val realtime = abs(realtimeUs() - ptsUs) <= abs(monotonicUs() - ptsUs)
        val switched = realtime != useRealtime
        useRealtime = realtime
        return switched
    }

    fun wallMsFor(ptsUs: Long): Long = wallMs() - (nowUs() - ptsUs) / 1_000
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
// Each parameter is the session identity, a port, or a C1 timing the recorder wires per tier.
@Suppress("LongParameterList")
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
        val open = current
        if (closed || (open == null && !isKeyframe)) {
            return
        }
        val segment = when {
            open == null -> openSegment(ptsUs)
            isKeyframe && ptsUs - open.startPtsUs >= segmentDurationUs - frameDurationUs / 2 -> {
                closeSegment(open, endPtsUs = ptsUs)
                openSegment(ptsUs)
            }
            else -> {
                requestSyncIfNear(ptsUs - open.startPtsUs)
                open
            }
        }
        current = segment
        segment.muxer.writeVideo(timebase.relative90k(ptsUs), annexB, isKeyframe, videoConfig)
        segment.frames += 1
        segment.lastPtsUs = ptsUs
    }

    /** Raw AAC frames; dropped until the first video segment opens. */
    @Synchronized
    @Throws(IOException::class)
    fun onAudioFrame(ptsUs: Long, aacRaw: ByteArray) {
        // finish() and abort() clear [current], so a closed segmenter returns here too.
        val segment = current ?: return
        if (!hasAudio || ptsUs < timebase.baseUs) {
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

    private fun requestSyncIfNear(elapsedUs: Long) {
        if (!syncRequested && elapsedUs >= segmentDurationUs - 2 * frameDurationUs) {
            syncRequested = true
            requestSyncFrame()
        }
    }

    private fun openSegment(startPtsUs: Long): OpenSegment {
        val seq = lastSeq + 1
        val open = OpenSegment(seq, startPtsUs, File(directory, "%06d.ts%s".format(seq, PART_SUFFIX)), hasAudio)
        syncRequested = false
        timebase.anchor(startPtsUs)
        return open
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

    /** `<seq>.ts.part` open for writing: bytes go through the SHA-256 digest into the muxer's file. */
    private class OpenSegment(val seq: Long, val startPtsUs: Long, val partFile: File, hasAudio: Boolean) {
        val fileStream = FileOutputStream(partFile)
        val digest: MessageDigest = MessageDigest.getInstance("SHA-256")
        val stream = BufferedOutputStream(DigestOutputStream(fileStream, digest), BUFFER_BYTES)
        val muxer = MpegTsMuxer(hasAudio).also { it.attach(stream) }
        var frames = 0
        var lastPtsUs = startPtsUs
    }

    companion object {
        const val PART_SUFFIX = ".part"
        private const val BUFFER_BYTES = 256 * 1024
        private const val TAG = "CourtSegmenter"
    }
}

internal fun ByteArray.toHex(): String = toByteString().hex()
