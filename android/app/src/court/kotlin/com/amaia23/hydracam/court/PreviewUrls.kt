package com.amaia23.hydracam.court

import java.net.URI
import java.net.URISyntaxException

/** Where an enrolled phone publishes its preview by default: `court/<courtId>/<slot>`. */
data class PreviewIdentity(val courtId: String, val slot: String) {
    val path: String get() = "court/$courtId/$slot"
}

/**
 * The URLs to try in order (SRT first, then the RTMPS fallback) and a credential-free [key]:
 * two targets with the same key are the same relay path, whatever token they carry.
 */
class PreviewTarget(val urls: List<String>, val key: String) {
    override fun toString(): String = "PreviewTarget($key, ${urls.size} url(s))"
}

/**
 * C4 publish URLs (H8). SRT carries the JWT in the MediaMTX streamid password slot
 * (`publish:<path>:<user>:<pass>`); RTMPS takes it as `?token=`. Plain RTMP is loopback only.
 */
object PreviewUrls {
    private const val SRT = "srt"
    private const val RTMPS = "rtmps"
    private const val RTMP = "rtmp"
    private const val RTMPS_PORT = 1936
    private const val STREAM_ID = "streamid="
    private const val PUBLISH = "publish:"
    private const val DEVICE_USER = ":device:"
    private val LOOPBACK = setOf("localhost", "127.0.0.1", "[::1]", "::1")

    fun isAllowed(url: String): Boolean {
        val uri = parse(url) ?: return false
        return when (uri.scheme.lowercase()) {
            SRT, RTMPS -> true
            RTMP -> uri.host.lowercase() in LOOPBACK
            else -> false
        }
    }

    fun target(publishUrl: String, token: String, identity: PreviewIdentity): PreviewTarget {
        val uri = requireNotNull(parse(publishUrl)) { "invalid publish url" }
        val authority = "${uri.host}${if (uri.port >= 0) ":${uri.port}" else ""}"
        return if (uri.scheme.lowercase() == SRT) {
            srt(uri, authority, token, identity)
        } else {
            val path = uri.rawPath.trim('/').ifEmpty { identity.path }
            PreviewTarget(listOf("${uri.scheme}://$authority/$path?token=$token"), "${uri.host}/$path")
        }
    }

    /** Scheme, host, port and path only; any query (streamid, token) becomes `?…`. */
    fun redact(url: String): String {
        val uri = parse(url) ?: return "<invalid url>"
        val port = if (uri.port >= 0) ":${uri.port}" else ""
        val path = uri.rawPath.orEmpty().trimEnd('/')
        val query = if (uri.rawQuery != null) "?…" else ""
        return "${uri.scheme}://${uri.host}$port$path$query"
    }

    private fun srt(uri: URI, authority: String, token: String, identity: PreviewIdentity): PreviewTarget {
        val params = uri.rawQuery?.split('&')?.filter { it.isNotEmpty() }.orEmpty()
        val streamId = params.firstOrNull { it.startsWith(STREAM_ID) }?.removePrefix(STREAM_ID)
        val path = streamId?.removePrefix(PUBLISH)?.substringBefore(':')?.ifEmpty { null } ?: identity.path
        val withCredentials = when {
            streamId == null -> "$PUBLISH$path$DEVICE_USER$token"
            streamId.contains(DEVICE_USER) -> streamId
            else -> "$streamId$DEVICE_USER$token"
        }
        val query = if (streamId == null) {
            params + "$STREAM_ID$withCredentials"
        } else {
            params.map { if (it.startsWith(STREAM_ID)) "$STREAM_ID$withCredentials" else it }
        }
        val fallback = "$RTMPS://${uri.host}:$RTMPS_PORT/$path?token=$token"
        return PreviewTarget(listOf("$SRT://$authority?${query.joinToString("&")}", fallback), "${uri.host}/$path")
    }

    private fun parse(url: String): URI? {
        val uri = try {
            URI(url.trim())
        } catch (ignored: URISyntaxException) {
            return null
        }
        return uri.takeIf { !it.scheme.isNullOrEmpty() && !it.host.isNullOrEmpty() }
    }
}
