package com.amaia23.hydracam.court

import android.util.Size
import android.view.Surface

typealias PreviewCameraControl = com.amaia23.hydracam.phonecore.PreviewCameraControl

/**
 * H8 seam (S2 implements it; contracts C4 v1.7). The preview surface stays in the capture session
 * from camera open to close, and toggling only changes the repeating burst: never rebuild the
 * session (400–530 ms, recorder gaps). The preview has its own encoder, never the proxy.
 */
interface CourtPreviewSeam : PreviewCameraControl {
    /** Sizes the dedicated preview encoder may use. */
    fun previewOutputSizes(): List<Size>

    /** Must be set before the camera opens; null removes the preview output at the next open. */
    fun setPreviewSurface(surface: Surface?)

    /** Device wall time of a frame's SENSOR_TIMESTAMP (BOOTTIME or MONOTONIC, see [PtsClock]). */
    fun captureWallMs(sensorNs: Long): Long
}
