package com.amaia23.hydracam.court

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.view.Surface
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

/** Android lifecycle only: frame contents and EGL rendering are verified on the actual camera. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class CourtPreviewFanoutTest {
    @Before
    fun androidSentinelsWithoutANativeGlDriver() {
        // Robolectric does not initialize EGL's native sentinel handles. No rendering is mocked:
        // this test deliberately never starts GL and only exercises queued-callback shutdown.
        ReflectionHelpers.setStaticField(EGL14::class.java, "EGL_NO_DISPLAY", mock(EGLDisplay::class.java))
        ReflectionHelpers.setStaticField(EGL14::class.java, "EGL_NO_CONTEXT", mock(EGLContext::class.java))
    }

    @Test
    fun aLateCameraFrameAfterReleaseCannotTouchDestroyedGlResources() {
        val fanout = CourtPreviewFanout(emptyList(), 1280, 720, 30)
        val texture = mock(SurfaceTexture::class.java)
        val surface = mock(Surface::class.java)
        ReflectionHelpers.setField(fanout, "texture", texture)
        ReflectionHelpers.setField(fanout, "inputSurface", surface)

        fanout.release()
        // A frame callback already queued on the GL looper can still arrive during quitSafely.
        fanout.onFrameAvailable(texture)

        verify(texture).setOnFrameAvailableListener(null)
        verify(texture).release()
        verify(surface).release()
        assertEquals(0L, fanout.framesDrawn.get())
    }

    @Test
    fun releaseAlsoHandlesASetupThatFailedBeforeCreatingSurfaces() {
        val fanout = CourtPreviewFanout(emptyList(), 1280, 720, 30)
        fanout.release()
        fanout.onFrameAvailable(mock(SurfaceTexture::class.java))
        assertEquals(0L, fanout.framesDrawn.get())
    }
}
