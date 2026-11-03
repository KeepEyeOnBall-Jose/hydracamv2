// swift-tools-version: 5.9
import PackageDescription
import Foundation

let runnerDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().appendingPathComponent("Runner")

let package = Package(
  name: "HydraCamManualExposure",
  platforms: [.macOS(.v10_15)],
  targets: [
    .target(
      name: "ManualExposure",
      path: "Runner",
      exclude: [
        "AppDelegate.swift", "AVManualExposureDevice.swift", "Assets.xcassets",
        "Base.lproj", "GeneratedPluginRegistrant.h", "GeneratedPluginRegistrant.m",
        "Info.plist", "PrivacyInfo.xcprivacy", "Runner-Bridging-Header.h",
        "xcode_backend_wrapper.sh"
      ].filter { FileManager.default.fileExists(atPath: runnerDirectory.appendingPathComponent($0).path) },
      sources: ["ManualExposureController.swift"]
    ),
    .testTarget(
      name: "ManualExposureTests",
      dependencies: ["ManualExposure"],
      path: "Tests"
    )
  ]
)
