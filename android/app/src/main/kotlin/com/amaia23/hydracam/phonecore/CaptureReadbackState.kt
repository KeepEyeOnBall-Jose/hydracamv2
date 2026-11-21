package com.amaia23.hydracam.phonecore

/** Cross-thread evidence for only the current repeating-request generation. */
class CaptureReadbackState {
    private var generation = 0L
    private var observed: CaptureReadback? = null

    /** Invalidates immediately, including while a control-thread rewarm waits for the camera handler. */
    @Synchronized
    fun reset(): Long {
        generation += 1
        observed = null
        return generation
    }

    /** An old callback cannot transition controls or clear a newer generation's evidence. */
    @Synchronized
    fun transition(expected: Long): Long? = if (generation == expected) reset() else null

    /** The tag comes from the completed Camera2 request, never from the current planned controls. */
    @Synchronized
    fun completed(requestTag: Any?, result: CaptureReadback): Boolean {
        if (requestTag != generation) return false
        observed = result
        return true
    }

    @Synchronized
    fun latest(): CaptureReadback? = observed
}
