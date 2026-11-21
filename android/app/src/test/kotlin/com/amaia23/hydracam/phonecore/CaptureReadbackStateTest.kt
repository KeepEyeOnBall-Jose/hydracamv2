package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureReadbackStateTest {
    @Test
    fun supersedesStaleGenerationsAndTracksLatestObservedReadback() {
        val state = CaptureReadbackState()
        assertNull(state.latest())

        val gen1 = state.reset()
        val first = CaptureReadback(aeLock = true, awbLock = true, sensitivity = 678)
        assertTrue(state.completed(gen1, first))
        assertEquals(first, state.latest())

        val gen2 = state.reset()
        assertNull(state.latest())
        assertFalse(state.completed(gen1, first))
        val second = CaptureReadback(aeLock = false, awbLock = false, sensitivity = 907)
        assertTrue(state.completed(gen2, second))

        val gen3 = state.transition(gen2)!!
        assertNull(state.latest())
        assertFalse(state.completed(gen2, second))
        assertNull(state.transition(gen2))

        val third = CaptureReadback(aeLock = true, awbLock = true, sensitivity = 907)
        assertTrue(state.completed(gen3, third))
        assertFalse(state.completed(null, first))
        assertEquals(third, state.latest())

        state.reset()
        assertFalse(state.completed(gen3, third))
        assertNull(state.latest())
    }
}
