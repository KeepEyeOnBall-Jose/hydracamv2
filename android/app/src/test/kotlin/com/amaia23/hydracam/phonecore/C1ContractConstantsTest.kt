package com.amaia23.hydracam.phonecore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class C1ContractConstantsTest {
    @Test
    fun protocolAndContractVersionMatchC1Object() {
        assertEquals(1, C1ContractConstants.VERSION)
        assertEquals(C1ContractConstants.VERSION, C1.VERSION)
        assertEquals("1.29", C1ContractConstants.CONTRACT_VERSION)
        assertEquals(C1ContractConstants.CONTRACT_VERSION, C1.CONTRACT_VERSION)
        val versionRegex = Regex(C1ContractConstants.CONTRACT_VERSION_PATTERN)
        assertTrue(versionRegex.matches(C1ContractConstants.CONTRACT_VERSION))
        assertFalse(versionRegex.matches("1"))
    }

    @Test
    fun messageTypesMatchC1AndPartitionCleanly() {
        assertEquals(
            listOf(C1.ACK, C1.NACK),
            C1ContractConstants.MessageType.BIDIRECTIONAL,
        )
        assertEquals(
            listOf(
                C1.ACK,
                C1.NACK,
                C1.HELLO,
                C1.STATE,
                C1.CLOCK_PING,
                C1.RECORDING_STARTED,
                C1.RECORDING_SEGMENT,
                C1.RECORDING_STOPPED,
                C1.RECORDING_GAP,
                C1.GESTURE_DETECTED,
            ),
            C1ContractConstants.MessageType.DEVICE_TO_CLOUD,
        )
        assertEquals(
            listOf(
                C1.ACK,
                C1.NACK,
                C1.CLOCK_PONG,
                C1.PREVIEW_START,
                C1.PREVIEW_STOP,
                C1.RECORD_PREPARE,
                C1.RECORD_START,
                C1.RECORD_STOP,
                C1.SIGNAL_EMIT,
                C1.SNAPSHOT,
                C1.UPLOAD_POLICY,
                C1.MASTERS_UPLOAD,
                C1.CONFIG_SET,
                C1.APP_UPDATE,
                C1.LOGS_UPLOAD,
            ),
            C1ContractConstants.MessageType.CLOUD_TO_DEVICE,
        )
        val expectedAll = (
            C1ContractConstants.MessageType.BIDIRECTIONAL +
                C1ContractConstants.MessageType.DEVICE_TO_CLOUD +
                C1ContractConstants.MessageType.CLOUD_TO_DEVICE
            ).distinct()
        assertEquals(expectedAll, C1ContractConstants.MessageType.ALL)
    }

    @Test
    fun nackCodesAndModesMatchPhoneCoreTypes() {
        assertEquals(
            listOf(
                C1NackCode.NOT_ROOTED,
                C1NackCode.BUSY,
                C1NackCode.BAD_REQUEST,
                C1NackCode.UNSUPPORTED,
                C1NackCode.NOT_ENROLLED,
                C1NackCode.INTERNAL,
                C1NackCode.TIMEOUT,
                C1NackCode.GONE,
                C1NackCode.NOT_PREPARED,
                C1NackCode.BAD_RANGE,
                C1NackCode.STORAGE_FULL,
            ),
            C1ContractConstants.NackCode.ALL,
        )

        assertEquals(
            C1ContractConstants.DeviceModeWire.ALL,
            C1ContractConstants.DeviceMode.entries.map { it.wire },
        )
        assertEquals(
            C1ContractConstants.DeviceModeWire.ALL,
            CourtMode.entries.map { it.wire },
        )
        assertEquals(listOf(StateBody.BLOCKED_STORAGE_FULL), C1ContractConstants.BlockedReason.ALL)
        assertEquals(StateBody.BLOCKED_STORAGE_FULL, CourtStateMachine.REASON_STORAGE_FULL)
    }

    @Test
    fun captureProfilePreviewSignalAndGestureConstantsMatchCoreModels() {
        assertEquals(C1.TIERS, C1ContractConstants.Tier.ALL)
        assertEquals(listOf(TsPartRecovery.REASON_NO_COMPLETE_FRAME), C1ContractConstants.GapReason.ALL)
        assertEquals(
            listOf(
                UploadPolicy.MODE_NEVER,
                UploadPolicy.MODE_ON_REQUEST,
                UploadPolicy.MODE_WINDOW,
                UploadPolicy.MODE_STREAM,
            ),
            C1ContractConstants.MasterMode.ALL,
        )
        assertEquals(
            listOf(CaptureTarget.LENS_WIDE, CaptureTarget.LENS_ULTRAWIDE, CaptureTarget.LENS_TELE),
            C1ContractConstants.Lens.ALL,
        )
        assertEquals(
            listOf(CaptureTarget.CODEC_AVC, CaptureTarget.CODEC_HEVC),
            C1ContractConstants.VideoCodec.ALL,
        )
        assertEquals(listOf(0, 90, 180, 270), C1ContractConstants.Rotation.DEGREES)
        assertEquals(C1ContractConstants.Rotation.DEG_180, CapturePlanner.HALF_TURN)

        assertEquals(listOf("2160p", "1080p", "720p"), C1ContractConstants.Profile.MASTER_RESOLUTIONS)
        assertEquals(listOf(30, 60), C1ContractConstants.Profile.FPS_OPTIONS)
        assertEquals(C1ContractConstants.Profile.PROXY_RES, RecordProfile.DEFAULT.proxyRes)
        assertEquals(C1ContractConstants.Profile.PROXY_KBPS, RecordProfile.DEFAULT.proxyKbps)
        assertEquals(C1ContractConstants.Profile.SEGMENT_S, RecordProfile.DEFAULT.segmentS)

        assertEquals(C1ContractConstants.Preview.WIDTH.toLong(), PreviewStart.WIDTH)
        assertEquals(C1ContractConstants.Preview.HEIGHT.toLong(), PreviewStart.HEIGHT)
        assertEquals(C1ContractConstants.Preview.FPS.toLong(), PreviewStart.FPS)
        assertEquals(1, C1ContractConstants.Preview.KBPS_MIN)
        assertEquals(1_000, C1ContractConstants.Preview.KBPS_MAX)

        assertEquals(
            listOf(
                SignalPatterns.COUNTDOWN,
                SignalPatterns.REC_START,
                SignalPatterns.REC_STOP,
                SignalPatterns.MARKER_ACK,
                SignalPatterns.LEASE_WARN,
                SignalPatterns.ERROR,
                SignalPatterns.SYNC_FLASH,
            ),
            C1ContractConstants.SignalId.ALL,
        )
        C1ContractConstants.SignalId.ALL.forEach { signalId ->
            assertNotNull("Expected signal pattern for $signalId", SignalPatterns.forSignal(signalId))
        }
        assertEquals(listOf("review", "highlight"), C1ContractConstants.GestureId.ALL)
    }

    @Test
    fun patternsAndBoundsValidateExpectedInputs() {
        assertEquals(512, C1ContractConstants.STREAM_ID_MAX_BYTES)
        val streamIdRegex = Regex(C1ContractConstants.STREAM_ID_PATTERN)
        val validToken = "a123456789012345678901"
        assertTrue(streamIdRegex.matches("publish:court/court-1/center:device:$validToken"))
        assertFalse(streamIdRegex.matches("publish:court/court-1/center:device:short"))

        val tokenRegex = Regex(C1ContractConstants.PUBLISH_TOKEN_PATTERN)
        assertTrue(tokenRegex.matches(validToken))
        assertFalse(tokenRegex.matches("too-short"))

        val shaRegex = Regex(C1ContractConstants.SHA256_PATTERN)
        assertTrue(shaRegex.matches("0123456789abcdef".repeat(4)))
        assertFalse(shaRegex.matches("0123456789ABCDEF".repeat(4)))
    }
}
