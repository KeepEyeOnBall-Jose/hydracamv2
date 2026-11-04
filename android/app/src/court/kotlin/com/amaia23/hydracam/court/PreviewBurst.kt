package com.amaia23.hydracam.court

/**
 * H8: the preview never rebuilds the capture session. The camera keeps the recording's fps and
 * only the repeating burst changes: request `i` of the burst also feeds the preview surface when
 * [pattern]`[i]` is true. The true entries are spread Bresenham-style, so 30 → 20 is 2 of every 3.
 */
object PreviewBurst {
    fun pattern(cameraFps: Int, previewFps: Int): List<Boolean> {
        require(cameraFps > 0) { "camera fps must be positive" }
        return when {
            previewFps <= 0 -> listOf(false)
            previewFps >= cameraFps -> listOf(true)
            else -> List(cameraFps / gcd(cameraFps, previewFps)) { i ->
                (i.toLong() * previewFps) % cameraFps <
                    previewFps
            }
        }
    }

    private tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)
}
