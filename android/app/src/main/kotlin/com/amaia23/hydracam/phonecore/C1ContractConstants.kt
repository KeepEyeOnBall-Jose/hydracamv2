// GENERATED FILE - DO NOT EDIT BY HAND.
// Source: packages/court-contracts (CONTRACT_VERSION = "1.29")
// Generator: packages/court-contracts/scripts/generate-mobile-c1.ts

package com.amaia23.hydracam.phonecore

/**
 * Deterministic C1 protocol constants derived from @media-timelines/court-contracts.
 */
object C1ContractConstants {
    const val VERSION: Int = 1
    const val CONTRACT_VERSION: String = "1.29"
    const val CONTRACT_VERSION_PATTERN: String = """^\d+(?:\.\d+)+$"""
    const val STREAM_ID_MAX_BYTES: Int = 512
    const val STREAM_ID_PATTERN: String =
        """^publish:court/([A-Za-z0-9_-]{1,64})/([A-Za-z0-9_-]{1,64}):device:([A-Za-z0-9_-]{22,128})$"""
    const val PUBLISH_TOKEN_PATTERN: String = """^[A-Za-z0-9_-]{22,128}$"""
    const val SHA256_PATTERN: String = """^[0-9a-f]{64}$"""

    object MessageType {
        // Bidirectional
        const val ACK: String = "ack"
        const val NACK: String = "nack"

        // Device -> Cloud
        const val HELLO: String = "hello"
        const val STATE: String = "state"
        const val CLOCK_PING: String = "clock.ping"
        const val RECORDING_STARTED: String = "recording.started"
        const val RECORDING_SEGMENT: String = "recording.segment"
        const val RECORDING_STOPPED: String = "recording.stopped"
        const val RECORDING_GAP: String = "recording.gap"
        const val GESTURE_DETECTED: String = "gesture.detected"

        // Cloud -> Device
        const val CLOCK_PONG: String = "clock.pong"
        const val PREVIEW_START: String = "preview.start"
        const val PREVIEW_STOP: String = "preview.stop"
        const val RECORD_PREPARE: String = "record.prepare"
        const val RECORD_START: String = "record.start"
        const val RECORD_STOP: String = "record.stop"
        const val SIGNAL_EMIT: String = "signal.emit"
        const val SNAPSHOT: String = "snapshot"
        const val UPLOAD_POLICY: String = "upload.policy"
        const val MASTERS_UPLOAD: String = "masters.upload"
        const val CONFIG_SET: String = "config.set"
        const val APP_UPDATE: String = "app.update"
        const val LOGS_UPLOAD: String = "logs.upload"

        val BIDIRECTIONAL: List<String> = listOf(ACK, NACK)
        val DEVICE_TO_CLOUD: List<String> = listOf(
            ACK,
            NACK,
            HELLO,
            STATE,
            CLOCK_PING,
            RECORDING_STARTED,
            RECORDING_SEGMENT,
            RECORDING_STOPPED,
            RECORDING_GAP,
            GESTURE_DETECTED,
        )
        val CLOUD_TO_DEVICE: List<String> = listOf(
            ACK,
            NACK,
            CLOCK_PONG,
            PREVIEW_START,
            PREVIEW_STOP,
            RECORD_PREPARE,
            RECORD_START,
            RECORD_STOP,
            SIGNAL_EMIT,
            SNAPSHOT,
            UPLOAD_POLICY,
            MASTERS_UPLOAD,
            CONFIG_SET,
            APP_UPDATE,
            LOGS_UPLOAD,
        )
        val ALL: List<String> = listOf(
            ACK,
            NACK,
            HELLO,
            STATE,
            CLOCK_PING,
            RECORDING_STARTED,
            RECORDING_SEGMENT,
            RECORDING_STOPPED,
            RECORDING_GAP,
            GESTURE_DETECTED,
            CLOCK_PONG,
            PREVIEW_START,
            PREVIEW_STOP,
            RECORD_PREPARE,
            RECORD_START,
            RECORD_STOP,
            SIGNAL_EMIT,
            SNAPSHOT,
            UPLOAD_POLICY,
            MASTERS_UPLOAD,
            CONFIG_SET,
            APP_UPDATE,
            LOGS_UPLOAD,
        )
    }

    object NackCode {
        const val NOT_ROOTED: String = "not_rooted"
        const val BUSY: String = "busy"
        const val BAD_REQUEST: String = "bad_request"
        const val UNSUPPORTED: String = "unsupported"
        const val NOT_ENROLLED: String = "not_enrolled"
        const val INTERNAL: String = "internal"
        const val TIMEOUT: String = "timeout"
        const val GONE: String = "gone"
        const val NOT_PREPARED: String = "not_prepared"
        const val BAD_RANGE: String = "bad_range"
        const val STORAGE_FULL: String = "storage_full"

        val ALL: List<String> = listOf(
            NOT_ROOTED,
            BUSY,
            BAD_REQUEST,
            UNSUPPORTED,
            NOT_ENROLLED,
            INTERNAL,
            TIMEOUT,
            GONE,
            NOT_PREPARED,
            BAD_RANGE,
            STORAGE_FULL,
        )
    }

    object DeviceModeWire {
        const val IDLE: String = "idle"
        const val PREVIEWING: String = "previewing"
        const val ARMED: String = "armed"
        const val RECORDING: String = "recording"
        const val UPLOADING: String = "uploading"
        const val UPDATING: String = "updating"
        const val DEGRADED: String = "degraded"
        const val ERROR: String = "error"

        val ALL: List<String> = listOf(IDLE, PREVIEWING, ARMED, RECORDING, UPLOADING, UPDATING, DEGRADED, ERROR)
    }

    enum class DeviceMode(val wire: String) {
        IDLE(DeviceModeWire.IDLE),
        PREVIEWING(DeviceModeWire.PREVIEWING),
        ARMED(DeviceModeWire.ARMED),
        RECORDING(DeviceModeWire.RECORDING),
        UPLOADING(DeviceModeWire.UPLOADING),
        UPDATING(DeviceModeWire.UPDATING),
        DEGRADED(DeviceModeWire.DEGRADED),
        ERROR(DeviceModeWire.ERROR),
    }

    object BlockedReason {
        const val STORAGE_FULL: String = "storage_full"

        val ALL: List<String> = listOf(STORAGE_FULL)
    }

    object Tier {
        const val PROXY: String = "proxy"
        const val MASTER: String = "master"

        val ALL: List<String> = listOf(PROXY, MASTER)
    }

    object GapReason {
        const val NO_COMPLETE_FRAME: String = "no-complete-frame"

        val ALL: List<String> = listOf(NO_COMPLETE_FRAME)
    }

    object MasterMode {
        const val NEVER: String = "never"
        const val ON_REQUEST: String = "on-request"
        const val WINDOW: String = "window"
        const val STREAM: String = "stream"

        val ALL: List<String> = listOf(NEVER, ON_REQUEST, WINDOW, STREAM)
    }

    object Lens {
        const val WIDE: String = "wide"
        const val ULTRAWIDE: String = "ultrawide"
        const val TELE: String = "tele"

        val ALL: List<String> = listOf(WIDE, ULTRAWIDE, TELE)
    }

    object VideoCodec {
        const val AVC: String = "avc"
        const val HEVC: String = "hevc"

        val ALL: List<String> = listOf(AVC, HEVC)
    }

    object Rotation {
        const val DEG_0: Int = 0
        const val DEG_90: Int = 90
        const val DEG_180: Int = 180
        const val DEG_270: Int = 270

        val DEGREES: List<Int> = listOf(DEG_0, DEG_90, DEG_180, DEG_270)
    }

    object Profile {
        const val MASTER_RES_2160P: String = "2160p"
        const val MASTER_RES_1080P: String = "1080p"
        const val MASTER_RES_720P: String = "720p"
        val MASTER_RESOLUTIONS: List<String> = listOf(MASTER_RES_2160P, MASTER_RES_1080P, MASTER_RES_720P)
        const val FPS_30: Int = 30
        const val FPS_60: Int = 60
        val FPS_OPTIONS: List<Int> = listOf(FPS_30, FPS_60)
        const val PROXY_RES: String = "720p"
        const val PROXY_KBPS: Int = 2000
        const val SEGMENT_S: Int = 6
    }

    object Preview {
        const val WIDTH: Int = 640
        const val HEIGHT: Int = 360
        const val FPS: Int = 20
        const val KBPS_MIN: Int = 1
        const val KBPS_MAX: Int = 1000
    }

    object SignalId {
        const val COUNTDOWN: String = "countdown"
        const val REC_START: String = "rec.start"
        const val REC_STOP: String = "rec.stop"
        const val MARKER_ACK: String = "marker.ack"
        const val LEASE_WARN: String = "lease.warn"
        const val ERROR: String = "error"
        const val SYNC_FLASH: String = "sync.flash"

        val ALL: List<String> = listOf(COUNTDOWN, REC_START, REC_STOP, MARKER_ACK, LEASE_WARN, ERROR, SYNC_FLASH)
    }

    object GestureId {
        const val REVIEW: String = "review"
        const val HIGHLIGHT: String = "highlight"

        val ALL: List<String> = listOf(REVIEW, HIGHLIGHT)
    }
}
