package com.amaia23.hydracam.court

/** Keeps every log line so tests can assert on what was reported. */
class RecordingLogger : CourtLogger {
    val infos = mutableListOf<String>()
    val warnings = mutableListOf<String>()

    @Synchronized
    override fun info(tag: String, message: String) {
        infos += message
    }

    @Synchronized
    override fun warn(tag: String, message: String, error: Throwable?) {
        warnings += message
    }
}
