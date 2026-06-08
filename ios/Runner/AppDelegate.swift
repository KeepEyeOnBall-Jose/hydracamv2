import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
}

class SceneDelegate: FlutterSceneDelegate {
}
