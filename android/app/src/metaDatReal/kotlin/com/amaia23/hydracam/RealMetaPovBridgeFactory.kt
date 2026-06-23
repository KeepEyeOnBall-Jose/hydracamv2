package com.amaia23.hydracam

import android.content.Context

/**
 * Gated factory (compiled when `-PwithMetaDat=true`).
 *
 * Returns the real Meta DAT POV bridge scaffold. The bridge reports
 * isAvailable()=false until the developer-preview Meta DAT SDK and the physical
 * Ray-Ban stream path are wired in the dedicated integration step, so even the
 * gated build never falsely claims continuous DAT capture — [MainActivity]
 * keeps using the mock/rolling-highlight fallback until a live stream exists.
 */
object RealMetaPovBridgeFactory {
    fun createOrNull(context: Context): WearablePovBridge? = RealMetaPovBridge(context)
}
