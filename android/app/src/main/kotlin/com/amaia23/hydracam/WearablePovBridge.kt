package com.amaia23.hydracam

/**
 * Seam for player-worn Ray-Ban Meta POV capture.
 *
 * The default (flavorless) build compiles a stub factory whose
 * [RealMetaPovBridgeFactory.createOrNull] returns null, so the
 * `hydracamv2/wearable_replay` channel keeps using the mock/rolling-highlight
 * POV path in [MainActivity]. The gated `-PwithMetaDat=true` build compiles the
 * real factory, whose bridge will drive the Meta Wearables Device Access
 * Toolkit once that developer-preview SDK is wired in the dedicated physical
 * DAT integration step.
 */
interface WearablePovBridge {
    /** True only when a real, authorized Meta DAT capture stream can be started. */
    fun isAvailable(): Boolean

    /** Start a POV capture; returns the recording payload (paths, timing, audio). */
    fun startCapture(request: Map<String, Any?>): Map<String, Any?>

    /** Stop a POV capture by recordingId; returns the finalized payload. */
    fun stopCapture(recordingId: String): Map<String, Any?>
}
