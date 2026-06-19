package com.amaia23.hydracam.fixedcamera

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FixedCameraHlsPlaylistWriterTest {
    @Test
    fun chunkFileNamePadsChunkNumberToEightDigits() {
        assertEquals(
            "fixed-court-a-game-1-00000000.m4s",
            FixedCameraHlsPlaylistWriter.chunkFileName("fixed-court-a", "game-1", 0),
        )
        assertEquals(
            "fixed-court-a-game-1-00000012.m4s",
            FixedCameraHlsPlaylistWriter.chunkFileName("fixed-court-a", "game-1", 12),
        )
        assertEquals(
            "fixed-court-a-game-1-12345678.m4s",
            FixedCameraHlsPlaylistWriter.chunkFileName("fixed-court-a", "game-1", 12_345_678),
        )
    }

    @Test
    fun renderFinalPlaylistMatchesFragmentedMp4HlsContract() {
        val playlist = FixedCameraHlsPlaylistWriter.render(
            initFileName = "init.mp4",
            segments = listOf(
                FixedCameraHlsPlaylistWriter.Segment(
                    fileName = "fixed-court-a-game-1-00000000.m4s",
                    durationSeconds = 1.971,
                ),
                FixedCameraHlsPlaylistWriter.Segment(
                    fileName = "fixed-court-a-game-1-00000001.m4s",
                    durationSeconds = 2.004,
                ),
            ),
            isFinal = true,
        )

        assertEquals(
            """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:3
            #EXT-X-MEDIA-SEQUENCE:0
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-MAP:URI="init.mp4"
            #EXTINF:1.971,
            fixed-court-a-game-1-00000000.m4s
            #EXTINF:2.004,
            fixed-court-a-game-1-00000001.m4s
            #EXT-X-ENDLIST
            """.trimIndent() + "\n",
            playlist,
        )
    }

    @Test
    fun writeCreatesParentDirectories() {
        val root = Files.createTempDirectory("hydracam-hls-playlist-test").toFile()
        val playlistFile = File(root, "nested/playlist.m3u8")

        FixedCameraHlsPlaylistWriter.write(
            file = playlistFile,
            initFileName = "init.mp4",
            segments = listOf(
                FixedCameraHlsPlaylistWriter.Segment(
                    fileName = "fixed-court-a-game-1-00000000.m4s",
                    durationSeconds = 2.0,
                ),
            ),
            isFinal = false,
        )

        assertTrue(playlistFile.exists())
        assertEquals(
            false,
            playlistFile.readText().contains("#EXT-X-ENDLIST"),
        )
    }
}
