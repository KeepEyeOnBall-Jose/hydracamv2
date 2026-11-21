package com.amaia23.hydracam.court

import com.amaia23.hydracam.phonecore.toHex as phonecoreToHex

typealias SegmentRecord = com.amaia23.hydracam.phonecore.SegmentRecord
typealias SegmentSeqStore = com.amaia23.hydracam.phonecore.SegmentSeqStore
typealias InMemorySegmentSeqStore = com.amaia23.hydracam.phonecore.InMemorySegmentSeqStore
typealias CourtStorage = com.amaia23.hydracam.phonecore.CourtStorage
typealias SegmentSidecarReader = com.amaia23.hydracam.phonecore.SegmentSidecarReader
typealias JsonlAppender = com.amaia23.hydracam.phonecore.JsonlAppender
typealias SessionTimebase = com.amaia23.hydracam.phonecore.SessionTimebase
internal typealias PtsClock = com.amaia23.hydracam.phonecore.PtsClock
typealias TsSegmenter = com.amaia23.hydracam.phonecore.TsSegmenter

internal fun ByteArray.toHex(): String = phonecoreToHex()
