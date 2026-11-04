package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Test

/** H5/S1: a `record.prepare` never inherits the 3A lock the live preview or an earlier session took. */
class PipelineActionTest {
    private val profile = RecordProfile.DEFAULT
    private val other = RecordProfile(fps = 25)

    @Test
    fun aClosedCameraOpens() {
        assertEquals(PipelineAction.OPEN, pipelineAction(null, null, profile, "s1"))
        assertEquals(PipelineAction.OPEN, pipelineAction(null, null, profile, null))
    }

    @Test
    fun anotherProfileReopens() {
        assertEquals(PipelineAction.REOPEN, pipelineAction(other, "s1", profile, "s1"))
        assertEquals(PipelineAction.REOPEN, pipelineAction(other, null, profile, null))
    }

    @Test
    fun aPrepareWarmsUpAgainWhenThePreviewOrAnEarlierSessionLockedTheCamera() {
        // The preview opened the camera (and locked 3A under whatever light it had then).
        assertEquals(PipelineAction.REWARM, pipelineAction(profile, null, profile, "s1"))
        // The preview kept the camera open past session s0's recording.
        assertEquals(PipelineAction.REWARM, pipelineAction(profile, "s0", profile, "s1"))
    }

    @Test
    fun aResentPrepareStartAndPreviewHoldKeepTheWarmUp() {
        assertEquals(PipelineAction.REUSE, pipelineAction(profile, "s1", profile, "s1"))
        // record.start and the preview hold pass no session.
        assertEquals(PipelineAction.REUSE, pipelineAction(profile, "s1", profile, null))
        assertEquals(PipelineAction.REUSE, pipelineAction(profile, null, profile, null))
    }
}
