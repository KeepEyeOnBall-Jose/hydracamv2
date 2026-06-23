package com.amaia23.hydracam

import android.content.Context

/**
 * Default-build factory (compiled when `-PwithMetaDat` is absent/false).
 *
 * No Meta DAT SDK is present in this build, so this returns null and the
 * wearable channel uses the proven mock/rolling-highlight POV fallback. This
 * keeps the wearable-replay dependency boundary green: the developer-preview
 * SDK never enters the default lane.
 */
object RealMetaPovBridgeFactory {
    fun createOrNull(context: Context): WearablePovBridge? = null
}
