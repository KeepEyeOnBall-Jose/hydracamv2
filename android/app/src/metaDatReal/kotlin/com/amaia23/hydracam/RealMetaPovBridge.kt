package com.amaia23.hydracam

import android.content.Context

/**
 * Scaffold for the real Meta Wearables Device Access Toolkit (DAT) POV bridge.
 *
 * TODO(meta-dat): integrate the developer-preview Meta DAT SDK behind this
 * class, gated by the `-PwithMetaDat=true` build:
 *  - add the DAT dependency to the gated build only (keep it out of the default
 *    lane so the wearable-replay dependency boundary stays green),
 *  - discover/connect the paired Ray-Ban Meta device via DAT,
 *  - request POV camera + audio stream access and start a capture session,
 *  - persist captured media under the app wearable_replay output directory with
 *    the same recording payload keys the mock path uses
 *    (recordingId, mediaPath, startedAt, endedAt, captureMode, hasAudio), and
 *  - flip [isAvailable] to reflect a live, authorized DAT stream.
 *
 * Until then this reports unavailable so [MainActivity] keeps using the proven
 * mock/rolling-highlight fallback and never claims continuous DAT capture.
 */
class RealMetaPovBridge(private val context: Context) : WearablePovBridge {
    override fun isAvailable(): Boolean = false

    override fun startCapture(request: Map<String, Any?>): Map<String, Any?> =
        throw IllegalStateException(NOT_IMPLEMENTED)

    override fun stopCapture(recordingId: String): Map<String, Any?> =
        throw IllegalStateException(NOT_IMPLEMENTED)

    private companion object {
        const val NOT_IMPLEMENTED =
            "Real Meta DAT POV capture is not yet implemented; mock fallback is used."
    }
}
