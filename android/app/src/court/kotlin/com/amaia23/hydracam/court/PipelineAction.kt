package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.pipelineAction as phonecorePipelineAction

internal typealias PipelineAction = com.amaia23.hydracam.phonecore.PipelineAction

internal fun <K> pipelineAction(open: K?, warmedFor: String?, wanted: K, sessionId: String?): PipelineAction =
    phonecorePipelineAction(open, warmedFor, wanted, sessionId)
