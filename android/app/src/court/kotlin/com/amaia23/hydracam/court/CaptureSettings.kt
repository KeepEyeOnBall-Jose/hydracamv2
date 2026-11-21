package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.appliedCapture as phonecoreAppliedCapture

typealias LensInfo = com.amaia23.hydracam.phonecore.LensInfo
typealias CapturePlanResult = com.amaia23.hydracam.phonecore.CapturePlanResult
typealias CaptureUnsupported = com.amaia23.hydracam.phonecore.CaptureUnsupported
typealias CapturePlan = com.amaia23.hydracam.phonecore.CapturePlan
typealias CapturePlanner = com.amaia23.hydracam.phonecore.CapturePlanner
typealias CaptureReadback = com.amaia23.hydracam.phonecore.CaptureReadback
typealias EncoderReadback = com.amaia23.hydracam.phonecore.EncoderReadback

const val MIME_AVC = com.amaia23.hydracam.phonecore.MIME_AVC
const val MIME_HEVC = com.amaia23.hydracam.phonecore.MIME_HEVC

fun appliedCapture(plan: CapturePlan, captureResult: CaptureReadback?, encoder: EncoderReadback): AppliedCapture? =
    phonecoreAppliedCapture(plan, captureResult, encoder)
