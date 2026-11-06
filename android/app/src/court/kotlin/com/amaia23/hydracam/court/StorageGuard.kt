package com.amaia23.hydracam.court

/**
 * C1 1.11 storage guard. A session fits when `free − reserve >= seconds × (proxyKbps + masterKbps)`;
 * the phone refuses sessions that do not fit, reports `blocked` below ten minutes, and stops a
 * recording before the next segment would eat into the reserve. Nothing here deletes anything.
 */
class StorageGuard(private val freeBytes: () -> Long, private val reserveBytes: Long = RESERVE_BYTES) {
    /** Bytes [seconds] of both tiers take at [profile]'s bitrates. */
    fun bytesFor(seconds: Long, profile: RecordProfile): Long =
        seconds * (profile.proxyKbps + profile.masterKbps) * BYTES_PER_KBPS_SECOND_NUM / BITS_PER_BYTE

    /** True when [seconds] of recording do not fit above the reserve. */
    fun refuses(seconds: Long, profile: RecordProfile): Boolean =
        freeBytes() - reserveBytes < bytesFor(seconds, profile)

    /** `state.blocked`: fewer than [BLOCKED_BELOW_S] seconds fit. */
    fun blocked(profile: RecordProfile): Boolean = refuses(BLOCKED_BELOW_S, profile)

    /** Mid-recording: the next segment would not fit above the reserve. */
    fun exhausted(profile: RecordProfile): Boolean = refuses(profile.segmentS.toLong(), profile)

    companion object {
        /** 2 GiB kept free for the OS, the database and the upload queue. */
        const val RESERVE_BYTES = 2L * 1024 * 1024 * 1024

        /** `state.blocked` while less than ten minutes of recording fit. */
        const val BLOCKED_BELOW_S = 600L

        private const val BYTES_PER_KBPS_SECOND_NUM = 1_000L
        private const val BITS_PER_BYTE = 8L
    }
}
