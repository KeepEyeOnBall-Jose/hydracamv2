package com.amaia23.hydracam.court

class FakeClock(var now: Long = 1_700_000_000_000L) : CourtClock {
    override fun nowMs(): Long = now
}
