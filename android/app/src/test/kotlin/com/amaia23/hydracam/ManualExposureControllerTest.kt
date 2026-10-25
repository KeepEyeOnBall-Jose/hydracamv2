package com.amaia23.hydracam

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.core.Camera
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraInfo
import androidx.core.content.ContextCompat
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.SettableFuture
import io.flutter.plugins.camerax.HydracamCaptureHooks
import java.util.concurrent.Executor
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.MockedStatic
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Exercises the actual controller through its method-channel-facing operations. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ManualExposureControllerTest {
    private lateinit var hooks: MockedStatic<HydracamCaptureHooks>
    private lateinit var controls: MockedStatic<Camera2CameraControl>
    private lateinit var infos: MockedStatic<Camera2CameraInfo>
    private lateinit var executors: MockedStatic<ContextCompat>
    private lateinit var controller: ManualExposureController
    private lateinit var camera: Camera
    private lateinit var cameraInfo: CameraInfo
    private lateinit var cameraControl: CameraControl
    private lateinit var control: Camera2CameraControl
    private lateinit var previous: CaptureRequestOptions

    @Before
    fun setUp() {
        val context = mock(Context::class.java)
        camera = mock(Camera::class.java)
        cameraInfo = mock(CameraInfo::class.java)
        cameraControl = mock(CameraControl::class.java)
        val info = mock(Camera2CameraInfo::class.java)
        control = mock(Camera2CameraControl::class.java)
        previous = CaptureRequestOptions.Builder()
            .setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
            .build()
        `when`(camera.cameraInfo).thenReturn(cameraInfo)
        `when`(camera.cameraControl).thenReturn(cameraControl)
        `when`(info.cameraId).thenReturn("0")
        `when`(info.getCameraCharacteristic(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES))
            .thenReturn(intArrayOf(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR))
        `when`(control.getCaptureRequestOptions()).thenReturn(previous)
        `when`(control.addCaptureRequestOptions(any(CaptureRequestOptions::class.java)))
            .thenReturn(Futures.immediateFuture(null))

        hooks = mockStatic(HydracamCaptureHooks::class.java)
        hooks.`when`<Camera> { HydracamCaptureHooks.getBoundCamera() }.thenReturn(camera)
        controls = mockStatic(Camera2CameraControl::class.java)
        controls.`when`<Camera2CameraControl> { Camera2CameraControl.from(cameraControl) }.thenReturn(control)
        infos = mockStatic(Camera2CameraInfo::class.java)
        infos.`when`<Camera2CameraInfo> { Camera2CameraInfo.from(cameraInfo) }.thenReturn(info)
        executors = mockStatic(ContextCompat::class.java)
        executors.`when`<Executor> { ContextCompat.getMainExecutor(context) }
            .thenReturn(Executor { command -> command.run() })
        controller = ManualExposureController(context)
        assertEquals("locked", apply().single()["status"])
    }

    @After
    fun tearDown() {
        if (::executors.isInitialized) executors.close()
        if (::infos.isInitialized) infos.close()
        if (::controls.isInitialized) controls.close()
        if (::hooks.isInitialized) hooks.close()
    }

    @Test
    fun failedRestorationRetriesTheOriginalOptions() {
        `when`(control.setCaptureRequestOptions(any(CaptureRequestOptions::class.java)))
            .thenReturn(Futures.immediateFailedFuture(IllegalStateException("restore rejected")))
            .thenReturn(Futures.immediateFuture(null))

        assertEquals("error", release().single()["status"])
        assertEquals("released", release().single()["status"])

        val options = ArgumentCaptor.forClass(CaptureRequestOptions::class.java)
        verify(control, times(2)).setCaptureRequestOptions(options.capture())
        options.allValues.forEach { assertSame(previous, it) }
        assertEquals("not_locked", release().single()["status"])
    }

    @Test
    fun concurrentRestoresShareTheNativeAcknowledgement() {
        val restoration = SettableFuture.create<Void>()
        `when`(control.setCaptureRequestOptions(any(CaptureRequestOptions::class.java)))
            .thenReturn(restoration)
        val first = release()
        val second = release()
        assertTrue(first.isEmpty())
        assertTrue(second.isEmpty())
        verify(control, times(1)).setCaptureRequestOptions(previous)

        restoration.set(null)

        assertEquals("released", first.single()["status"])
        assertEquals(first, second)
    }

    @Test
    fun applyCannotOverwriteAnUnsettledRestoration() {
        val restoration = SettableFuture.create<Void>()
        `when`(control.setCaptureRequestOptions(any(CaptureRequestOptions::class.java)))
            .thenReturn(restoration)
        val release = release()

        assertEquals("error", apply(exposureTimeNs = 8_333_333L).single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java))
        assertTrue(release.isEmpty())
        restoration.set(null)
        assertEquals("released", release.single()["status"])
    }

    @Test
    fun applyCannotOverwriteAFailedRestorationBeforeRetry() {
        `when`(control.setCaptureRequestOptions(any(CaptureRequestOptions::class.java)))
            .thenReturn(Futures.immediateFailedFuture(IllegalStateException("restore rejected")))
            .thenReturn(Futures.immediateFuture(null))
        assertEquals("error", release().single()["status"])

        assertEquals("error", apply(exposureTimeNs = 8_333_333L).single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java))
        assertEquals("released", release().single()["status"])
        verify(control, times(2)).setCaptureRequestOptions(previous)
    }

    private fun apply(exposureTimeNs: Long = 16_666_667L): MutableList<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        controller.applyLock(exposureTimeNs, 33_333_333L) { results.add(it) }
        return results
    }

    private fun release(): MutableList<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        controller.release { results.add(it) }
        return results
    }
}
