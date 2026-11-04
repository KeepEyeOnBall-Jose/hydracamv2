package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** C4: SRT puts the JWT in the streamid password slot; the RTMPS fallback takes it as `token=`. */
class PreviewUrlsTest {
    private val identity = PreviewIdentity(courtId = "club-7", slot = "left")

    @Test
    fun barePublishUrlGetsTheEnrolledPathAndAnRtmpsFallback() {
        val target = PreviewUrls.target("srt://relay.example.invalid:8890", "jwt-1", identity)

        assertEquals(
            listOf(
                "srt://relay.example.invalid:8890?streamid=publish:court/club-7/left:device:jwt-1",
                "rtmps://relay.example.invalid:1936/court/club-7/left?token=jwt-1",
            ),
            target.urls,
        )
        assertEquals("relay.example.invalid/court/club-7/left", target.key)
    }

    @Test
    fun k2StreamIdIsKeptAndItsPathFeedsTheFallback() {
        val url = "srt://relay:8890?streamid=publish:court/club-9/right:device:jwt-2"
        val target = PreviewUrls.target(url, "jwt-2", identity)

        assertEquals(url, target.urls[0])
        assertEquals("rtmps://relay:1936/court/club-9/right?token=jwt-2", target.urls[1])
        assertEquals("relay/court/club-9/right", target.key)
    }

    @Test
    fun streamIdWithoutCredentialsGetsTheToken() {
        val target = PreviewUrls.target("srt://relay:8890?latency=300&streamid=publish:court/a/b", "jwt", identity)

        assertEquals("srt://relay:8890?latency=300&streamid=publish:court/a/b:device:jwt", target.urls[0])
        assertEquals("relay/court/a/b", target.key)
    }

    @Test
    fun otherQueryParametersAreKept() {
        val target = PreviewUrls.target("srt://relay:8890?latency=300", "jwt", identity)

        assertEquals("srt://relay:8890?latency=300&streamid=publish:court/club-7/left:device:jwt", target.urls[0])
    }

    @Test
    fun rtmpPublishUrlsHaveNoFallback() {
        val bare = PreviewUrls.target("rtmps://relay:1936", "jwt", identity)
        val withPath = PreviewUrls.target("rtmps://relay:1936/court/x/y?token=old", "jwt", identity)
        val loopback = PreviewUrls.target("rtmp://127.0.0.1:1935/court/x/y", "jwt", identity)

        assertEquals(listOf("rtmps://relay:1936/court/club-7/left?token=jwt"), bare.urls)
        assertEquals(listOf("rtmps://relay:1936/court/x/y?token=jwt"), withPath.urls)
        assertEquals(listOf("rtmp://127.0.0.1:1935/court/x/y?token=jwt"), loopback.urls)
        assertEquals("relay/court/x/y", withPath.key)
    }

    @Test
    fun aNewTokenForTheSamePathIsTheSameTarget() {
        val first = PreviewUrls.target("srt://relay:8890", "jwt-1", identity)
        val second = PreviewUrls.target("srt://relay:8890", "jwt-2", identity)
        val elsewhere = PreviewUrls.target("srt://relay:8890", "jwt-2", PreviewIdentity("club-7", "right"))

        assertEquals(first.key, second.key)
        assertNotEquals(first.urls, second.urls)
        assertNotEquals(first.key, elsewhere.key)
    }

    @Test
    fun redactionHidesCredentialsEverywhere() {
        val target = PreviewUrls.target("srt://relay:8890", "jwt-secret", identity)

        assertEquals("srt://relay:8890?…", PreviewUrls.redact(target.urls[0]))
        assertEquals("rtmps://relay:1936/court/club-7/left?…", PreviewUrls.redact(target.urls[1]))
        assertEquals("rtmps://relay:1936/court/club-7/left", PreviewUrls.redact("rtmps://relay:1936/court/club-7/left"))
        assertEquals("<invalid url>", PreviewUrls.redact("srt://bad host?x"))
        assertFalse(target.toString(), target.toString().contains("jwt-secret"))
        assertTrue(target.toString(), target.toString().contains("relay/court/club-7/left"))
    }
}
