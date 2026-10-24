import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var wearablePovCaptures: [String: [String: Any]] = [:]
  private let manualExposure = ManualExposureController()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerLaunchConfigChannel(binaryMessenger: messenger)
    registerVideoMetadataChannel(binaryMessenger: messenger)
    registerWearableReplayChannel(binaryMessenger: messenger)
    registerManualExposureChannel(binaryMessenger: messenger)
  }

  private func registerLaunchConfigChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "hydracamv2/launch_config",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getLaunchConfig" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self.buildLaunchConfig())
    }
  }

  private func buildLaunchConfig() -> [String: Any] {
    let environment = ProcessInfo.processInfo.environment
    var payload: [String: Any] = [:]

    if let role = environment["HYDRACAM_AUTOMATION_ROLE"], !role.isEmpty {
      payload["role"] = role
    }
    if let preferredMasterIp = environment["HYDRACAM_AUTOMATION_MASTER_IP"],
       !preferredMasterIp.isEmpty {
      payload["preferredMasterIp"] = preferredMasterIp
    }
    if let targetId = environment["HYDRACAM_AUTOMATION_TARGET_ID"],
       !targetId.isEmpty {
      payload["automationTargetId"] = targetId
    }
    if let forceSlaveMode = environment["HYDRACAM_AUTOMATION_FORCE_SLAVE"],
       !forceSlaveMode.isEmpty {
      payload["forceSlaveMode"] = ["1", "true", "yes"].contains(forceSlaveMode.lowercased())
    }

    return payload
  }

  private func registerVideoMetadataChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "hydracamv2/video_metadata",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "inspectVideo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(
          code: "missing_path",
          message: "path is required",
          details: nil
        ))
        return
      }
      result(self.buildVideoMetadata(path: path))
    }
  }

  private func buildVideoMetadata(path: String) -> [String: Any?] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      return [:]
    }
    let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let durationSeconds = CMTimeGetSeconds(asset.duration)
    let durationMs = durationSeconds.isFinite ? Int(durationSeconds * 1000) : nil

    return [
      "width": Int(abs(transformedSize.width)),
      "height": Int(abs(transformedSize.height)),
      "durationMs": durationMs,
      "framesPerSecond": Double(videoTrack.nominalFrameRate)
    ]
  }

  private func registerWearableReplayChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "hydracamv2/wearable_replay",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getCapabilities":
        result(self.buildWearableReplayCapabilities())
      case "pollWatchTelemetry":
        result(self.buildMockWatchTelemetry(arguments: call.arguments))
      case "startMetaPovCapture":
        self.startMockMetaPovCapture(arguments: call.arguments, result: result)
      case "stopMetaPovCapture":
        self.stopMockMetaPovCapture(arguments: call.arguments, result: result)
      case "sendFeedback":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func buildWearableReplayCapabilities() -> [String: Any] {
    [
      "platform": "ios",
      "channelAvailable": true,
      "metaDatAvailable": false,
      "metaMockAvailable": true,
      "watchCompanionAvailable": false,
      "watchMockAvailable": true,
      "supportsWatchHaptics": false,
      "supportsGlassesAudio": true,
      "supportsRollingPovFallback": true,
      "requiresPhysicalMetaHardware": true,
      "requiresPhysicalWatchHardware": true,
      "reason": "Mock Meta DAT and watch telemetry are available for simulator proof; physical Ray-Ban Meta and Galaxy Watch4 remain hardware gates."
    ]
  }

  private func buildMockWatchTelemetry(arguments: Any?) -> [String: Any] {
    let args = arguments as? [String: Any]
    let sourceDeviceId = (args?["sourceDeviceId"] as? String).flatMap {
      $0.isEmpty ? nil : $0
    } ?? "galaxy-watch4-sim"
    let heartRate = 145 + (Int(Date().timeIntervalSince1970) % 8)
    return [
      "sourceDeviceId": sourceDeviceId,
      "localTimestamp": isoTimestamp(Date()),
      "heartRateBpm": heartRate,
      "interBeatIntervalMs": 60000 / heartRate,
      "accelerometerX": 0.31,
      "accelerometerY": 0.42,
      "accelerometerZ": 9.62,
      "gyroscopeX": 0.11,
      "gyroscopeY": 0.07,
      "gyroscopeZ": 0.13,
      "motionIntensity": 0.76,
      "mockReading": true
    ]
  }

  private func startMockMetaPovCapture(arguments: Any?, result: FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let recordingId = args["recordingId"] as? String,
      !recordingId.isEmpty
    else {
      result(FlutterError(
        code: "invalid_meta_pov_request",
        message: "recordingId is required",
        details: nil
      ))
      return
    }

    let directory = wearableReplayOutputDirectory()
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let mediaUrl = directory.appendingPathComponent("\(recordingId)-mock-pov.mp4")
    try? "mock Ray-Ban Meta POV capture for \(recordingId)\n".write(
      to: mediaUrl,
      atomically: true,
      encoding: .utf8
    )
    let now = Date()
    let payload: [String: Any] = [
      "recordingId": recordingId,
      "mediaPath": mediaUrl.path,
      "startedAt": isoTimestamp(now),
      "endedAt": isoTimestamp(now),
      "captureMode": args["captureMode"] as? String ?? "continuous",
      "hasAudio": args["includeAudio"] as? Bool ?? true,
      "mockCapture": true
    ]
    wearablePovCaptures[recordingId] = payload
    result(payload)
  }

  private func stopMockMetaPovCapture(arguments: Any?, result: FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let recordingId = args["recordingId"] as? String,
      !recordingId.isEmpty
    else {
      result(FlutterError(
        code: "invalid_meta_pov_request",
        message: "recordingId is required",
        details: nil
      ))
      return
    }

    guard var payload = wearablePovCaptures[recordingId] else {
      result(FlutterError(
        code: "invalid_meta_pov_request",
        message: "Unknown recordingId: \(recordingId)",
        details: nil
      ))
      return
    }
    payload["endedAt"] = isoTimestamp(Date())
    wearablePovCaptures.removeValue(forKey: recordingId)
    result(payload)
  }

  private func wearableReplayOutputDirectory() -> URL {
    let base = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("wearable-replay", isDirectory: true)
  }

  private func isoTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

extension AppDelegate {
  fileprivate func registerManualExposureChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "hydracamv2/manual_exposure",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let cameraName = args["cameraName"] as? String
      switch call.method {
      case "applyLock":
        guard
          let exposureTimeNs = (args["exposureTimeNs"] as? NSNumber)?.int64Value,
          let frameDurationNs = (args["frameDurationNs"] as? NSNumber)?.int64Value
        else {
          result(FlutterError(
            code: "missing_arguments",
            message: "exposureTimeNs and frameDurationNs are required",
            details: nil
          ))
          return
        }
        self.manualExposure.applyLock(
          cameraName: cameraName,
          exposureTimeNs: exposureTimeNs,
          frameDurationNs: frameDurationNs
        ) { payload in
          DispatchQueue.main.async { result(payload) }
        }
      case "release":
        result(self.manualExposure.release(cameraName: cameraName))
      case "readCaptureSettings":
        result(self.manualExposure.readCaptureSettings(cameraName: cameraName))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Locks shutter (exposure duration), ISO, white balance and focus on the
/// AVCaptureDevice the camera plugin opened (its uniqueID is the Flutter
/// camera name). ISO is metered once from running auto exposure (shutter
/// priority) and then held. iOS does not report rolling-shutter readout time.
final class ManualExposureController {
  private struct PreviousModes {
    let exposure: AVCaptureDevice.ExposureMode
    let whiteBalance: AVCaptureDevice.WhiteBalanceMode
    let focus: AVCaptureDevice.FocusMode
  }

  private var lockedUniqueID: String?
  private var previousModes: PreviousModes?
  private var lockedRequest: [String: Any?]?

  func applyLock(
    cameraName: String?,
    exposureTimeNs: Int64,
    frameDurationNs: Int64,
    completion: @escaping ([String: Any?]) -> Void
  ) {
    guard let device = resolveDevice(cameraName) else {
      completion(["status": "no_camera"])
      return
    }
    guard device.isExposureModeSupported(.custom) else {
      completion(["status": "unsupported", "cameraId": device.uniqueID])
      return
    }
    let format = device.activeFormat
    var request: [String: Any?]
    if lockedUniqueID == device.uniqueID,
       let locked = lockedRequest,
       (locked["requestedExposureTimeNs"] as? Int64) == exposureTimeNs {
      request = locked
    } else {
      request = meterLockRequest(
        device: device,
        format: format,
        exposureTimeNs: exposureTimeNs,
        frameDurationNs: frameDurationNs
      )
    }
    do {
      try device.lockForConfiguration()
    } catch {
      completion([
        "status": "error",
        "cameraId": device.uniqueID,
        "error": error.localizedDescription
      ])
      return
    }
    if lockedUniqueID != device.uniqueID {
      previousModes = PreviousModes(
        exposure: device.exposureMode,
        whiteBalance: device.whiteBalanceMode,
        focus: device.focusMode
      )
    }
    if device.isWhiteBalanceModeSupported(.locked) {
      device.whiteBalanceMode = .locked
    }
    if device.isFocusModeSupported(.locked) {
      device.focusMode = .locked
    }
    let exposure = CMTime(
      value: request["exposureTimeNs"] as? Int64 ?? exposureTimeNs,
      timescale: 1_000_000_000
    )
    let iso = request["iso"] as? Float ?? format.maxISO
    device.setExposureModeCustom(duration: exposure, iso: iso) { _ in
      completion(request.merging([
        "status": "locked",
        "cameraId": device.uniqueID
      ]) { _, new in new })
    }
    device.unlockForConfiguration()
    lockedUniqueID = device.uniqueID
    lockedRequest = request
  }

  func release(cameraName: String?) -> [String: Any?] {
    defer {
      lockedUniqueID = nil
      lockedRequest = nil
      previousModes = nil
    }
    guard
      let device = resolveDevice(cameraName),
      device.uniqueID == lockedUniqueID
    else {
      return ["status": "not_locked"]
    }
    do {
      try device.lockForConfiguration()
    } catch {
      return [
        "status": "error",
        "cameraId": device.uniqueID,
        "error": error.localizedDescription
      ]
    }
    let exposureMode = previousModes?.exposure ?? .continuousAutoExposure
    let whiteBalanceMode = previousModes?.whiteBalance ?? .continuousAutoWhiteBalance
    let focusMode = previousModes?.focus ?? .continuousAutoFocus
    if device.isExposureModeSupported(exposureMode) {
      device.exposureMode = exposureMode
    }
    if device.isWhiteBalanceModeSupported(whiteBalanceMode) {
      device.whiteBalanceMode = whiteBalanceMode
    }
    if device.isFocusModeSupported(focusMode) {
      device.focusMode = focusMode
    }
    device.unlockForConfiguration()
    return ["status": "released", "cameraId": device.uniqueID]
  }

  /// Live values of the device; AVFoundation has no per-frame result here.
  func readCaptureSettings(cameraName: String?) -> [String: Any?] {
    guard let device = resolveDevice(cameraName) else {
      return ["status": "no_camera"]
    }
    let frameDuration = device.activeVideoMinFrameDuration
    let frameDurationNs = nanoseconds(frameDuration)
    let fps: Double? = frameDuration.seconds > 0 ? 1.0 / frameDuration.seconds : nil
    return [
      "status": "ok",
      "source": "avfoundation_device_state",
      "cameraId": device.uniqueID,
      "deviceType": device.deviceType.rawValue,
      "exposureTimeNs": nanoseconds(device.exposureDuration),
      "iso": Double(device.iso),
      "frameDurationNs": frameDurationNs,
      "maxFrameDurationNs": nanoseconds(device.activeVideoMaxFrameDuration),
      "fps": fps,
      "rollingShutterSkewNs": nil,
      "exposureMode": exposureModeName(device.exposureMode),
      "whiteBalanceMode": whiteBalanceModeName(device.whiteBalanceMode),
      "awbLocked": device.whiteBalanceMode == .locked,
      "focusMode": focusModeName(device.focusMode),
      "lensPosition": Double(device.lensPosition),
      "manualLockActive": lockedUniqueID == device.uniqueID
    ]
  }

  private func meterLockRequest(
    device: AVCaptureDevice,
    format: AVCaptureDevice.Format,
    exposureTimeNs: Int64,
    frameDurationNs: Int64
  ) -> [String: Any?] {
    let minExposureNs = nanoseconds(format.minExposureDuration) ?? 1
    let maxExposureNs = nanoseconds(format.maxExposureDuration) ?? exposureTimeNs
    let frameLimitNs = min(
      frameDurationNs,
      nanoseconds(device.activeVideoMaxFrameDuration) ?? frameDurationNs
    )
    let exposureNs = max(minExposureNs, min(exposureTimeNs, maxExposureNs, frameLimitNs))
    let autoExposureNs = nanoseconds(device.exposureDuration)
    let autoIso = device.iso
    var wantedIso = format.maxISO
    if let autoExposureNs, autoExposureNs > 0, autoIso > 0 {
      wantedIso = autoIso * Float(autoExposureNs) / Float(exposureNs)
    }
    let iso = max(format.minISO, min(wantedIso, format.maxISO))
    return [
      "requestedExposureTimeNs": exposureTimeNs,
      "exposureTimeNs": exposureNs,
      "iso": iso,
      "frameDurationNs": frameDurationNs,
      "meteredAutoExposureTimeNs": autoExposureNs,
      "meteredAutoIso": Double(autoIso),
      "wantedIso": Double(wantedIso),
      "isoMin": Double(format.minISO),
      "isoMax": Double(format.maxISO),
      "exposureClamped": exposureNs != exposureTimeNs,
      "underexposed": wantedIso > format.maxISO,
      "meteringSource": autoIso > 0 ? "auto_exposure" : "none_max_iso"
    ]
  }

  private func resolveDevice(_ cameraName: String?) -> AVCaptureDevice? {
    guard let cameraName, !cameraName.isEmpty else {
      return nil
    }
    return AVCaptureDevice(uniqueID: cameraName)
  }

  private func nanoseconds(_ time: CMTime) -> Int64? {
    guard time.isValid, time.isNumeric, time.timescale > 0 else {
      return nil
    }
    return Int64((Double(time.value) * 1_000_000_000.0 / Double(time.timescale)).rounded())
  }

  private func exposureModeName(_ mode: AVCaptureDevice.ExposureMode) -> String {
    switch mode {
    case .locked: return "locked"
    case .autoExpose: return "auto"
    case .continuousAutoExposure: return "continuous_auto"
    case .custom: return "custom"
    @unknown default: return "unknown"
    }
  }

  private func whiteBalanceModeName(_ mode: AVCaptureDevice.WhiteBalanceMode) -> String {
    switch mode {
    case .locked: return "locked"
    case .autoWhiteBalance: return "auto"
    case .continuousAutoWhiteBalance: return "continuous_auto"
    @unknown default: return "unknown"
    }
  }

  private func focusModeName(_ mode: AVCaptureDevice.FocusMode) -> String {
    switch mode {
    case .locked: return "locked"
    case .autoFocus: return "auto"
    case .continuousAutoFocus: return "continuous_auto"
    @unknown default: return "unknown"
    }
  }
}

class SceneDelegate: FlutterSceneDelegate {
}
