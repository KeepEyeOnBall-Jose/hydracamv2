package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.NoopPhoneLogger
import com.amaia23.hydracam.phonecore.PhoneClock
import com.amaia23.hydracam.phonecore.PhoneLogger

typealias CourtLogger = PhoneLogger
typealias NoopCourtLogger = NoopPhoneLogger
typealias CourtClock = PhoneClock
typealias HttpStatus = com.amaia23.hydracam.phonecore.HttpStatus
typealias ClockSample = com.amaia23.hydracam.phonecore.ClockSample
typealias ClockEstimate = com.amaia23.hydracam.phonecore.ClockEstimate
typealias ClockOffsetEstimator = com.amaia23.hydracam.phonecore.ClockOffsetEstimator
typealias ReconnectBackoff = com.amaia23.hydracam.phonecore.ReconnectBackoff
typealias RootStatus = com.amaia23.hydracam.phonecore.RootStatus
