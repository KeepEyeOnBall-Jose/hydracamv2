package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Pure JVM dependency boundary for `phonecore`: no Android framework (`android.*`, `androidx.*`
 * including Room), RootEncoder (`com.pedro.*`), or `court` flavor imports may leak into shared
 * `phonecore` code or tests. OkHttp/Okio are allowed shared transport dependencies.
 */
class PhoneCoreBoundaryTest {
    private fun resolveDir(subpath: String): File = listOf(
        File(subpath),
        File("app/$subpath"),
        File("android/app/$subpath"),
    ).firstOrNull { it.isDirectory }
        ?: error("Could not locate $subpath from ${File(".").absolutePath}")

    private fun stripComments(source: String): String {
        val withoutBlockComments = Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL).replace(source, "")
        return Regex("//.*").replace(withoutBlockComments, "")
    }

    private fun checkBoundary(dir: File, forbidden: List<String>, expectedFiles: Set<String>) {
        val files = dir.listFiles { file -> file.extension == "kt" }.orEmpty().sortedBy { it.name }
        assertTrue("Expected Kotlin files in ${dir.path}", files.isNotEmpty())
        val names = files.map { it.name }.toSet()
        expectedFiles.forEach { expected ->
            assertTrue("Missing $expected in ${dir.path}", expected in names)
        }
        for (file in files) {
            val text = file.readText()
            val lines = text.lines()
            val pkg = lines.firstOrNull { it.startsWith("package ") }?.trim()
            assertEquals("Unexpected package in ${file.name}", "package com.amaia23.hydracam.phonecore", pkg)

            val imports = lines.map { it.trim() }.filter { it.startsWith("import ") }
            for (line in imports) {
                val imported = line.removePrefix("import ").trim()
                for (prefix in forbidden) {
                    assertTrue(
                        "Forbidden import `$imported` in ${file.name}",
                        !imported.startsWith(prefix),
                    )
                }
            }

            if (file.name != "PhoneCoreBoundaryTest.kt") {
                val codeOnly = stripComments(text)
                for (prefix in forbidden) {
                    assertTrue(
                        "Forbidden direct reference `$prefix` in ${file.name}",
                        !codeOnly.contains(prefix),
                    )
                }
            }
        }
    }

    @Test
    fun mainPhoneCoreHasZeroAndroidOrCourtDependencies() {
        val mainDir = resolveDir("src/main/kotlin/com/amaia23/hydracam/phonecore")
        val forbidden = listOf(
            "android.",
            "androidx.",
            "com.amaia23.hydracam.court.",
            "com.amaia23.hydracam.fixedcamera.",
            "com.pedro.",
        )
        val expectedMainFiles = setOf(
            "C1Capture.kt",
            "C1ContractConstants.kt",
            "C1Protocol.kt",
            "C2Uploader.kt",
            "CaptureCapabilities.kt",
            "CaptureReadbackState.kt",
            "CaptureSettings.kt",
            "CaptureWarmup.kt",
            "CourtAuth.kt",
            "CourtCommandTable.kt",
            "CourtSignalPlayer.kt",
            "CourtStateMachine.kt",
            "CourtWsClient.kt",
            "CourtWsCore.kt",
            "DeviceTokenClient.kt",
            "EventOutbox.kt",
            "FileUploadQueueStore.kt",
            "MpegTsMuxer.kt",
            "PhoneCore.kt",
            "PhoneCoreLiveSessionUploader.kt",
            "PhoneCoreLiveUploadDispatcher.kt",
            "PipelineAction.kt",
            "PreviewBurst.kt",
            "PreviewController.kt",
            "PreviewRateGovernor.kt",
            "PreviewUrls.kt",
            "StorageGuard.kt",
            "TsPartRecovery.kt",
            "TsSegmenter.kt",
            "UploadLifecycle.kt",
            "UploadQueueStore.kt",
            "UploadThrottle.kt",
        )
        checkBoundary(mainDir, forbidden, expectedMainFiles)
    }

    @Test
    fun phoneCoreUnitTestsStayPureJvmWithoutAndroidOrMockingFrameworks() {
        val testDir = resolveDir("src/test/kotlin/com/amaia23/hydracam/phonecore")
        val forbidden = listOf(
            "android.",
            "androidx.",
            "com.amaia23.hydracam.court.",
            "com.amaia23.hydracam.fixedcamera.",
            "com.pedro.",
            "org.robolectric.",
            "org.mockito.",
        )
        val expectedTestFiles = setOf(
            "CaptureWarmupTest.kt",
            "DeviceTokenClientTest.kt",
            "FileUploadQueueStoreTest.kt",
            "PhoneCoreBoundaryTest.kt",
            "PhoneCoreLiveSessionUploaderTest.kt",
            "PhoneCoreLiveUploadDispatcherTest.kt",
        )
        checkBoundary(testDir, forbidden, expectedTestFiles)
    }
}
