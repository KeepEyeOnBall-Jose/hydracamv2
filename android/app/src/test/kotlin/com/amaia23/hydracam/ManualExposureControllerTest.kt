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
    private val owner = "b13f616c-4ae8-4fa2-87ae-0fa23222e2c4"
    private val nextOwner = "5d03e278-d2ed-44e4-9acb-afacb237cbe8"
    private lateinit var hooks: MockedStatic<HydracamCaptureHooks>
    private lateinit var executors: MockedStatic<ContextCompat>
    private lateinit var controller: ManualExposureController
    private lateinit var context: Context
    private lateinit var info: Camera2CameraInfo
    private lateinit var camera: Camera
    private lateinit var cameraInfo: CameraInfo
    private lateinit var cameraControl: CameraControl
    private lateinit var control: Camera2CameraControl
    private lateinit var previous: CaptureRequestOptions
    private var replacementControl: Camera2CameraControl? = null

    @Before
    fun setUp() {
        context = mock(Context::class.java)
        camera = mock(Camera::class.java)
        cameraInfo = mock(CameraInfo::class.java)
        cameraControl = mock(CameraControl::class.java)
        info = mock(Camera2CameraInfo::class.java)
        control = mock(Camera2CameraControl::class.java)
        previous = CaptureRequestOptions.Builder()
            .setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
            .build()
        `when`(camera.cameraInfo).thenReturn(cameraInfo)
        `when`(camera.cameraControl).thenReturn(cameraControl)
        `when`(info.getCameraCharacteristic(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES))
            .thenReturn(intArrayOf(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR))
        `when`(control.getCaptureRequestOptions()).thenReturn(previous)
        `when`(control.addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous))
            .thenReturn(Futures.immediateFuture(null))

        hooks = mockStatic(HydracamCaptureHooks::class.java)
        hooks.`when`<Camera> { HydracamCaptureHooks.getBoundCamera() }.thenReturn(camera)
        executors = mockStatic(ContextCompat::class.java)
        executors.`when`<Executor> { ContextCompat.getMainExecutor(context) }
            .thenReturn(Executor { command -> command.run() })
        controller = newController()
        assertEquals("locked", apply().single()["status"])
    }

    @After
    fun tearDown() {
        if (::executors.isInitialized) executors.close()
        if (::hooks.isInitialized) hooks.close()
    }

    @Test
    fun failedRestorationRetriesTheOriginalOptions() {
        `when`(control.setCaptureRequestOptions(previous))
            .thenReturn(Futures.immediateFailedFuture(IllegalStateException("restore rejected")))
            .thenReturn(Futures.immediateFuture(null))

        assertEquals("error", release().single()["status"])
        assertEquals("released", release().single()["status"])

        val options = ArgumentCaptor.forClass(CaptureRequestOptions::class.java)
        verify(control, times(2)).setCaptureRequestOptions(options.capture() ?: previous)
        options.allValues.forEach { assertSame(previous, it) }
        assertEquals("released", release().single()["status"])
    }

    @Test
    fun concurrentRestoresShareTheNativeAcknowledgement() {
        val restoration = SettableFuture.create<Void?>()
        `when`(control.setCaptureRequestOptions(previous))
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
        val restoration = SettableFuture.create<Void?>()
        `when`(control.setCaptureRequestOptions(previous))
            .thenReturn(restoration)
        val release = release()

        assertEquals("error", apply(exposureTimeNs = 8_333_333L).single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
        assertTrue(release.isEmpty())
        restoration.set(null)
        assertEquals("released", release.single()["status"])
    }

    @Test
    fun applyCannotOverwriteAFailedRestorationBeforeRetry() {
        `when`(control.setCaptureRequestOptions(previous))
            .thenReturn(Futures.immediateFailedFuture(IllegalStateException("restore rejected")))
            .thenReturn(Futures.immediateFuture(null))
        assertEquals("error", release().single()["status"])

        assertEquals("error", apply(exposureTimeNs = 8_333_333L).single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
        assertEquals("released", release().single()["status"])
        verify(control, times(2)).setCaptureRequestOptions(previous)
    }

    @Test
    fun sameOwnerRelockKeepsTheOriginalSnapshot() {
        val laterOptions = CaptureRequestOptions.Builder().build()
        `when`(control.getCaptureRequestOptions()).thenReturn(laterOptions)
        assertEquals("locked", apply().single()["status"])
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))

        assertEquals("released", release().single()["status"])
        verify(control, times(1)).getCaptureRequestOptions()
        verify(control).setCaptureRequestOptions(previous)
    }

    @Test
    fun aDifferentOwnerCannotReplaceAFailedRestoration() {
        `when`(control.setCaptureRequestOptions(previous))
            .thenReturn(Futures.immediateFailedFuture(IllegalStateException("restore rejected")))
            .thenReturn(Futures.immediateFuture(null))
        assertEquals("error", release().single()["status"])

        val foreign = apply(ownerId = nextOwner).single()
        assertEquals("busy", foreign["status"])
        assertEquals(false, foreign["cleanupRequired"])
        assertEquals("released", release().single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
    }

    @Test
    fun aSuccessfulRestorationAllowsTheNextOwner() {
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))
        assertEquals("released", release().single()["status"])
        assertEquals("locked", apply(ownerId = nextOwner).single()["status"])
        assertEquals("released", release(ownerId = nextOwner).single()["status"])
        verify(control, times(2)).getCaptureRequestOptions()
    }

    @Test
    fun wrongOwnerCannotReleaseTheLease() {
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))
        val foreign = release(ownerId = nextOwner).single()
        assertEquals("busy", foreign["status"])
        assertEquals(false, foreign["cleanupRequired"])
        verify(control, never()).setCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
        assertEquals("released", release().single()["status"])
    }

    @Test
    fun noOwnerReleaseAcknowledgesAnAlreadyCleanController() {
        controller = newController()
        val result = release().single()
        assertEquals("released", result["status"])
        assertEquals(false, result["cleanupRequired"])
        verify(control, never()).setCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
    }

    @Test
    fun wrongDeviceCannotReleaseTheLease() {
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))
        val wrongDevice = release(cameraName = "1").single()
        assertEquals("error", wrongDevice["status"])
        assertEquals(true, wrongDevice["cleanupRequired"])
        verify(control, never()).setCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
        assertEquals("released", release().single()["status"])
    }

    @Test
    fun sameOwnerCannotMoveToAnotherControlWithTheSameCameraId() {
        val replacement = mock(Camera::class.java)
        `when`(replacement.cameraControl).thenReturn(mock(CameraControl::class.java))
        val otherControl = mock(Camera2CameraControl::class.java)
        replacementControl = otherControl
        `when`(otherControl.getCaptureRequestOptions()).thenReturn(CaptureRequestOptions.Builder().build())
        `when`(otherControl.addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous))
            .thenReturn(Futures.immediateFuture(null))
        hooks.`when`<Camera> { HydracamCaptureHooks.getBoundCamera() }.thenReturn(replacement)

        val result = apply().single()
        assertEquals("error", result["status"])
        assertEquals(true, result["cleanupRequired"])
        verify(otherControl, never()).addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))
        assertEquals("released", release().single()["status"])
        verify(control).setCaptureRequestOptions(previous)
        verify(otherControl, never()).setCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
    }

    @Test
    fun applyFailureAfterMutationRetainsCleanupOwnership() {
        controller = newController()
        `when`(control.addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous))
            .thenReturn(Futures.immediateFailedFuture(IllegalStateException("apply rejected after submission")))
        val result = apply().single()
        assertEquals("error", result["status"])
        assertEquals(true, result["cleanupRequired"])
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))
        assertEquals("released", release().single()["status"])
        verify(control).setCaptureRequestOptions(previous)
    }

    @Test
    fun pendingApplyReservesTheOwner() {
        controller = newController()
        val pending = SettableFuture.create<Void?>()
        `when`(control.addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous))
            .thenReturn(pending)
        val applying = apply()
        val foreign = apply(ownerId = nextOwner)
        try {
            assertEquals(listOf("busy"), foreign.map { it["status"] })
            assertEquals(false, foreign.single()["cleanupRequired"])
        } finally {
            pending.set(null)
        }
        assertEquals("locked", applying.single()["status"])
    }

    @Test
    fun releaseWaitsForTheExactPendingApplyBeforeRestoring() {
        controller = newController()
        val pending = SettableFuture.create<Void?>()
        `when`(control.addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous))
            .thenReturn(pending)
        `when`(control.setCaptureRequestOptions(previous)).thenReturn(Futures.immediateFuture(null))
        val applying = apply()
        val releasing = release()
        try {
            assertTrue(applying.isEmpty())
            assertTrue(releasing.isEmpty())
            verify(control, never()).setCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
        } finally {
            pending.set(null)
        }

        assertEquals("locked", applying.single()["status"])
        assertEquals("released", releasing.single()["status"])
        verify(control).setCaptureRequestOptions(previous)
    }

    @Test
    fun unsupportedPreflightDoesNotReserveAnOwner() {
        controller = newController()
        `when`(info.getCameraCharacteristic(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES))
            .thenReturn(intArrayOf())
        val result = apply().single()
        assertEquals("unsupported", result["status"])
        assertEquals(false, result["cleanupRequired"])
        assertEquals("released", release().single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
    }

    @Test
    fun noCameraPreflightDoesNotReserveAnOwner() {
        controller = newController()
        hooks.`when`<Camera?> { HydracamCaptureHooks.getBoundCamera() }.thenReturn(null)
        val result = apply().single()
        assertEquals("no_camera", result["status"])
        assertEquals(false, result["cleanupRequired"])
        assertEquals("released", release().single()["status"])
        verify(control, times(1)).addCaptureRequestOptions(any(CaptureRequestOptions::class.java) ?: previous)
    }

    private fun newController() = ManualExposureController(
        context,
        infoFor = { info },
        controlFor = { if (it === camera) control else requireNotNull(replacementControl) },
        cameraIdFor = { "0" },
    )

    private fun apply(
        exposureTimeNs: Long = 16_666_667L,
        ownerId: String = owner,
        cameraName: String = "0",
    ): MutableList<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        controller.applyLock(ownerId, cameraName, exposureTimeNs, 33_333_333L) { results.add(it) }
        return results
    }

    private fun release(ownerId: String = owner, cameraName: String = "0"): MutableList<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        controller.release(ownerId, cameraName) { results.add(it) }
        return results
    }
}
