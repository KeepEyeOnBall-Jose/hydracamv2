package com.amaia23.hydracam.court

import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest

/** Media of one tier lost from [fromServerMs] on (C1 `recording.gap`): a crash left no whole frame. */
data class SegmentGap(val sessionId: String, val tier: String, val fromServerMs: Long, val reason: String)

/** What [TsSegmenter] knew when it opened `<seq>.ts.part`; a crash leaves it beside the part. */
internal data class PartMeta(val mediaStartServerMs: Long, val offsetMs: Long, val rttMs: Long) {
    fun write(file: File) {
        val json = JSONObject()
            .put("mediaStartServerMs", mediaStartServerMs)
            .put("offsetMs", offsetMs)
            .put("rttMs", rttMs)
        FileOutputStream(file).use { stream ->
            stream.write(json.toString().toByteArray(Charsets.UTF_8))
            stream.fd.sync()
        }
    }

    companion object {
        fun read(file: File): PartMeta? {
            val json = try {
                JSONObject(file.readText())
            } catch (ignored: IOException) {
                null
            } catch (ignored: JSONException) {
                null
            }
            val meta = json?.let {
                PartMeta(it.optLong("mediaStartServerMs", -1), it.optLong("offsetMs"), it.optLong("rttMs", -1))
            }
            return meta?.takeIf { it.mediaStartServerMs >= 0 }
        }
    }
}

/**
 * Closes the `<seq>.ts.part` a killed process left in one tier directory. MPEG-TS survives
 * truncation, so the file is cut before the last video PES (which may be torn) and committed as a
 * short segment with its real duration and SHA-256. A part with no whole frame is announced as a
 * gap instead. Parts without metadata, or not the next seq, are dropped.
 */
// Same session identity and ports as the TsSegmenter whose part this is.
@Suppress("LongParameterList")
class TsPartRecovery(
    private val sessionId: String,
    private val slot: String,
    private val tier: String,
    private val directory: File,
    private val sidecar: JsonlAppender,
    private val seqStore: SegmentSeqStore,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val logger: CourtLogger = NoopCourtLogger,
) {
    @Throws(IOException::class)
    fun recover(onSegment: (SegmentRecord) -> Unit, onGap: (SegmentGap) -> Unit) {
        val parts = directory.listFiles { file -> file.name.endsWith(TsSegmenter.PART_SUFFIX) }.orEmpty()
        parts.sortedBy { it.name }.forEach { part -> recoverPart(part, onSegment, onGap) }
        directory.listFiles { file -> file.name.endsWith(META_SUFFIX) }?.forEach { orphan ->
            logger.warn(TAG, "Dropping orphan ${orphan.name} for $sessionId/$tier.")
            orphan.delete()
        }
    }

    private fun recoverPart(part: File, onSegment: (SegmentRecord) -> Unit, onGap: (SegmentGap) -> Unit) {
        val metaFile = metaFile(part)
        val meta = PartMeta.read(metaFile)
        val seq = seqStore.lastSeq(sessionId, tier) + 1
        if (meta == null || part.name != partName(seq)) {
            logger.warn(TAG, "Dropping unfinished ${part.name} for $sessionId/$tier (not recoverable).")
            part.delete()
            metaFile.delete()
            return
        }
        val bytes = part.readBytes()
        val starts = videoPesStarts(bytes)
        if (starts.size < 2) {
            logger.warn(TAG, "Lost ${part.name} for $sessionId/$tier: $REASON_NO_COMPLETE_FRAME.")
            part.delete()
            metaFile.delete()
            onGap(SegmentGap(sessionId, tier, meta.mediaStartServerMs, REASON_NO_COMPLETE_FRAME))
            return
        }
        // The last PES has no length and may be torn, so the segment ends where it starts.
        val cut = starts.last()
        val durationMs = MpegTsMuxer.ms(cut.pts90k - starts[0].pts90k)
        val record = commit(part, seq, bytes, cut.offset, meta, starts.size - 1, durationMs)
        metaFile.delete()
        logger.info(TAG, "Recovered $sessionId/$tier seq=$seq ${record.bytes} B ${record.durationMs} ms.")
        onSegment(record)
    }

    @Suppress("LongParameterList")
    private fun commit(
        part: File,
        seq: Long,
        bytes: ByteArray,
        length: Int,
        meta: PartMeta,
        frames: Int,
        durationMs: Long,
    ): SegmentRecord {
        RandomAccessFile(part, "rw").use { raf ->
            raf.setLength(length.toLong())
            raf.fd.sync()
        }
        val finalFile = File(directory, "%06d.ts".format(seq))
        if (!part.renameTo(finalFile)) {
            throw IOException("Could not rename ${part.name}.")
        }
        val digest = MessageDigest.getInstance("SHA-256").apply { update(bytes, 0, length) }
        val record = SegmentRecord(
            sessionId = sessionId,
            slot = slot,
            tier = tier,
            seq = seq,
            file = finalFile,
            bytes = length.toLong(),
            sha256 = digest.digest().toHex(),
            mediaStartServerMs = meta.mediaStartServerMs,
            durationMs = durationMs,
            frames = frames,
            offsetMs = meta.offsetMs,
            rttMs = meta.rttMs,
        )
        sidecar.append(record.toSidecarJson(clock.nowMs()))
        seqStore.commitSeq(sessionId, tier, seq)
        return record
    }

    private class PesStart(val offset: Int, val pts90k: Long)

    /** Video PES starts among the whole, in-sync packets at the head of [bytes]. */
    private fun videoPesStarts(bytes: ByteArray): List<PesStart> {
        val starts = mutableListOf<PesStart>()
        var offset = 0
        while (MpegTsMuxer.isPacket(bytes, offset)) {
            MpegTsMuxer.videoPesPts(bytes, offset)?.let { pts -> starts += PesStart(offset, pts) }
            offset += MpegTsMuxer.PACKET_SIZE
        }
        return starts
    }

    companion object {
        const val REASON_NO_COMPLETE_FRAME = "no-complete-frame"
        const val META_SUFFIX = ".part.json"
        private const val TAG = "CourtPartRecovery"

        fun partName(seq: Long): String = "%06d.ts%s".format(seq, TsSegmenter.PART_SUFFIX)

        fun metaFile(part: File): File =
            File(part.parentFile, part.name.removeSuffix(TsSegmenter.PART_SUFFIX) + META_SUFFIX)
    }
}
