package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PreviewUrlsTest {
    private val identity = PreviewIdentity(courtId = "club-7", slot = "left")

    @Test
    fun buildsSrtTargetWithRtmpsFallback() {
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
    fun enforcesAllowedSchemesAndRedactsCredentials() {
        assertTrue(PreviewUrls.isAllowed("srt://relay.example:8890"))
        assertTrue(PreviewUrls.isAllowed("rtmps://relay.example:1936"))
        assertTrue(PreviewUrls.isAllowed("rtmp://127.0.0.1:1935/court/a/b"))
        assertFalse(PreviewUrls.isAllowed("rtmp://10.0.0.2:1935/court/a/b"))
        assertFalse(PreviewUrls.isAllowed("http://relay.example"))

        val first = PreviewUrls.target("srt://relay:8890", "jwt-secret", identity)
        val second = PreviewUrls.target("srt://relay:8890", "jwt-other", identity)
        assertEquals(first.key, second.key)
        assertNotEquals(first.urls, second.urls)
        assertEquals("srt://relay:8890?…", PreviewUrls.redact(first.urls[0]))
        assertEquals("rtmps://relay:1936/court/club-7/left?…", PreviewUrls.redact(first.urls[1]))
        assertEquals("<invalid url>", PreviewUrls.redact("srt://bad host?x"))
        assertFalse(first.toString().contains("jwt-secret"))
    }
}
