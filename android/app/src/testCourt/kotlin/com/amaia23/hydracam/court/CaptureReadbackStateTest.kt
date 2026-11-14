package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Delayed Camera2 callbacks must never restore evidence from superseded requests. */
class CaptureReadbackStateTest {
    @Test
    fun rewarmAndLockExcludeSupersededCallbacksBeforeAndAfterFreshEvidence() {
        val state = CaptureReadbackState()
        assertNull(state.latest())
        val previousSession = state.reset()
        val oldLocked = CaptureReadback(aeLock = true, awbLock = true, sensitivity = 678)
        assertTrue(state.completed(previousSession, oldLocked))

        val warming = state.reset()
        assertNull(state.latest())
        assertFalse(state.completed(previousSession, oldLocked))
        assertNull(state.latest())
        val warmResult = CaptureReadback(aeLock = false, awbLock = false, sensitivity = 907)
        assertTrue(state.completed(warming, warmResult))

        val locked = state.transition(warming)!!
        assertNull(state.latest())
        assertFalse(state.completed(warming, warmResult))
        val lockedResult = CaptureReadback(aeLock = true, awbLock = true, sensitivity = 907)
        assertTrue(state.completed(locked, lockedResult))
        assertFalse(state.completed(warming, warmResult))
        assertFalse(state.completed(previousSession, oldLocked))
        assertFalse(state.completed(null, oldLocked))
        assertNull(state.transition(warming))
        assertEquals(lockedResult, state.latest())

        state.reset()
        assertFalse(state.completed(locked, lockedResult))
        assertNull(state.latest())
    }
}
