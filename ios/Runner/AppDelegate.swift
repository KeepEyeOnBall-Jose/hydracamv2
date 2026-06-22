import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var wearablePovCaptures: [String: [String: Any]] = [:]

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

class SceneDelegate: FlutterSceneDelegate {
}
