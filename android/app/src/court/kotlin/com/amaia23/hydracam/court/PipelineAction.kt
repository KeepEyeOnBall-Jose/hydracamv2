package com.amaia23.hydracam.court

/** What [CourtCameraRecorder] does with its camera pipeline before it uses it. */
internal enum class PipelineAction { OPEN, REUSE, REWARM, REOPEN }

/**
 * [open] is the key (profile and capture) of the open pipeline (null: none), [warmedFor] the session whose
 * `record.prepare` last warmed its 3A up (null: the live preview opened it). [sessionId] is set for
 * `record.prepare` only: every session's master starts from its own warm-up, never from an AE/AWB/AF
 * lock the preview or an earlier session took under other light. `record.start` and the preview
 * hold pass null and keep whatever is open with the right key.
 */
internal fun <K> pipelineAction(open: K?, warmedFor: String?, wanted: K, sessionId: String?): PipelineAction = when {
    open == null -> PipelineAction.OPEN
    open != wanted -> PipelineAction.REOPEN
    sessionId != null && sessionId != warmedFor -> PipelineAction.REWARM
    else -> PipelineAction.REUSE
}
