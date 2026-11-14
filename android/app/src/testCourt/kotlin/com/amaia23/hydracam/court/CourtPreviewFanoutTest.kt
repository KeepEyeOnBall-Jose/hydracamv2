package com.amaia23.hydracam.court

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.view.Surface
import org.junit.Assert.assertArrayEquals
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
    @Test
    fun cameraSensorQuarterTurnsAreRemovedWithoutLosingCropOrGlFlip() {
        val nativeCrop = floatArrayOf(
            0.8f, 0f, 0f, 0f,
            0f, -0.6f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0.1f, 0.8f, 0f, 1f,
        )
        val cameraTransforms = mapOf(
            90 to floatArrayOf(
                0f, -0.6f, 0f, 0f,
                -0.8f, 0f, 0f, 0f,
                0f, 0f, 1f, 0f,
                0.9f, 0.8f, 0f, 1f,
            ),
            270 to floatArrayOf(
                0f, 0.6f, 0f, 0f,
                0.8f, 0f, 0f, 0f,
                0f, 0f, 1f, 0f,
                0.1f, 0.2f, 0f, 1f,
            ),
        )
        cameraTransforms.forEach { (sensorOrientation, matrix) ->
            CourtPreviewFanout.removeCameraRotation(matrix, sensorOrientation)
            assertArrayEquals("sensor $sensorOrientation", nativeCrop, matrix, 0.000001f)
            CourtPreviewFanout.rotateHalfTurn(matrix)
            assertArrayEquals(
                floatArrayOf(-0.8f, 0f, 0f, 0f, 0f, 0.6f, 0f, 0f, 0f, 0f, 1f, 0f, 0.9f, 0.2f, 0f, 1f),
                matrix,
                0.000001f,
            )
        }
    }

    @Test
    fun aHalfTurnMapsOppositeCornersInsideTheCameraTextureCrop() {
        // SurfaceTexture's vertical flip and crop must remain outside the image rotation.
        val cameraTransform = floatArrayOf(
            0.8f, 0f, 0f, 0f,
            0f, -0.6f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0.1f, 0.8f, 0f, 1f,
        )
        CourtPreviewFanout.rotateHalfTurn(cameraTransform)
        assertArrayEquals(floatArrayOf(-0.8f, 0f, 0f, 0f), cameraTransform.copyOfRange(0, 4), 0.000001f)
        assertArrayEquals(floatArrayOf(0f, 0.6f, 0f, 0f), cameraTransform.copyOfRange(4, 8), 0.000001f)
        assertArrayEquals(floatArrayOf(0.9f, 0.2f, 0f, 1f), cameraTransform.copyOfRange(12, 16), 0.000001f)
    }

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
