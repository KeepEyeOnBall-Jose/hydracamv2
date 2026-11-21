package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Test

class PipelineActionTest {
    private val profile = RecordProfile.DEFAULT
    private val other = RecordProfile(fps = 25)

    @Test
    fun selectsOpenReopenRewarmOrReuseByStateAndSession() {
        assertEquals(PipelineAction.OPEN, pipelineAction(null, null, profile, "s1"))
        assertEquals(PipelineAction.OPEN, pipelineAction(null, null, profile, null))

        assertEquals(PipelineAction.REOPEN, pipelineAction(other, "s1", profile, "s1"))
        assertEquals(PipelineAction.REOPEN, pipelineAction(other, null, profile, null))

        assertEquals(PipelineAction.REWARM, pipelineAction(profile, null, profile, "s1"))
        assertEquals(PipelineAction.REWARM, pipelineAction(profile, "s0", profile, "s1"))

        assertEquals(PipelineAction.REUSE, pipelineAction(profile, "s1", profile, "s1"))
        assertEquals(PipelineAction.REUSE, pipelineAction(profile, "s1", profile, null))
        assertEquals(PipelineAction.REUSE, pipelineAction(profile, null, profile, null))
    }
}
