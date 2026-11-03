package com.amaia23.hydracam.court

import android.util.Size
import android.view.Surface

/**
 * H8 seam (S2 implements it; contracts C4 v1.7). The preview surface stays in the capture session
 * from camera open to close, and toggling only changes the repeating burst: never rebuild the
 * session (400–530 ms, recorder gaps). The preview has its own encoder, never the proxy.
 */
interface CourtPreviewSeam {
    /** Sizes the dedicated preview encoder may use. */
    fun previewOutputSizes(): List<Size>

    /** Must be set before the camera opens; null removes the preview output at the next open. */
    fun setPreviewSurface(surface: Surface?)

    /** Changes only the repeating burst's preview target fps; 0 stops preview frames. */
    fun setPreviewFps(fps: Int)

    /** Keeps the camera open for live view without recording (R2: live view never records). */
    fun holdCameraForPreview(hold: Boolean)

    /** Device wall time of a frame's SENSOR_TIMESTAMP (BOOTTIME or MONOTONIC, see [PtsClock]). */
    fun captureWallMs(sensorNs: Long): Long
}
