package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.C1CoreEvents
import org.json.JSONObject
import com.amaia23.hydracam.phonecore.optLongOrNull as phonecoreOptLongOrNull
import com.amaia23.hydracam.phonecore.optStringOrNull as phonecoreOptStringOrNull

typealias ContractSkew = com.amaia23.hydracam.phonecore.ContractSkew
typealias C1 = com.amaia23.hydracam.phonecore.C1
typealias C1NackCode = com.amaia23.hydracam.phonecore.C1NackCode
typealias C1ProtocolException = com.amaia23.hydracam.phonecore.C1ProtocolException
typealias C1Envelope = com.amaia23.hydracam.phonecore.C1Envelope
typealias CourtMode = com.amaia23.hydracam.phonecore.CourtMode
typealias CourtCaps = com.amaia23.hydracam.phonecore.CourtCaps
typealias HelloBody = com.amaia23.hydracam.phonecore.HelloBody
typealias StateBody = com.amaia23.hydracam.phonecore.StateBody
typealias RecordProfile = com.amaia23.hydracam.phonecore.RecordProfile
typealias RecordPrepare = com.amaia23.hydracam.phonecore.RecordPrepare
typealias RecordStart = com.amaia23.hydracam.phonecore.RecordStart
typealias RecordStop = com.amaia23.hydracam.phonecore.RecordStop
typealias SignalEmit = com.amaia23.hydracam.phonecore.SignalEmit
typealias PreviewStart = com.amaia23.hydracam.phonecore.PreviewStart
typealias MastersUpload = com.amaia23.hydracam.phonecore.MastersUpload
typealias UploadPolicy = com.amaia23.hydracam.phonecore.UploadPolicy
typealias CourtIds = com.amaia23.hydracam.phonecore.CourtIds
typealias CourtUrls = com.amaia23.hydracam.phonecore.CourtUrls

object C1Events {
    fun recordingStarted(
        sessionId: String,
        firstFrameServerMs: Long,
        offsetMs: Long,
        profile: RecordProfile,
        applied: AppliedCapture? = null,
    ): JSONObject = C1CoreEvents.recordingStarted(sessionId, firstFrameServerMs, offsetMs, profile, applied)

    fun recordingSegment(segment: SegmentRecord): JSONObject = JSONObject()
        .put("sessionId", segment.sessionId)
        .put("tier", segment.tier)
        .put("seq", segment.seq)
        .put("bytes", segment.bytes)
        .put("sha256", segment.sha256)
        .put("mediaStartServerMs", segment.mediaStartServerMs)
        .put("durationMs", segment.durationMs)
        .put("frames", segment.frames)

    /** A crash lost one tier's media from `fromServerMs` up to the next `recording.segment`. */
    fun recordingGap(gap: SegmentGap): JSONObject = JSONObject()
        .put("sessionId", gap.sessionId)
        .put("tier", gap.tier)
        .put("fromServerMs", gap.fromServerMs)
        .put("reason", gap.reason)

    fun recordingStopped(sessionId: String, lastSeqProxy: Long, lastSeqMaster: Long, reason: String): JSONObject =
        C1CoreEvents.recordingStopped(sessionId, lastSeqProxy, lastSeqMaster, reason)
}

internal fun JSONObject.optStringOrNull(name: String): String? = phonecoreOptStringOrNull(name)

internal fun JSONObject.optLongOrNull(name: String): Long? = phonecoreOptLongOrNull(name)
