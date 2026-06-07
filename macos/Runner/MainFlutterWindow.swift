import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLaunchConfigChannel(flutterViewController: flutterViewController)

    super.awakeFromNib()
  }

  private func registerLaunchConfigChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "hydracamv2/launch_config",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
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
    if let forceSlaveMode = environment["HYDRACAM_AUTOMATION_FORCE_SLAVE"],
       !forceSlaveMode.isEmpty {
      payload["forceSlaveMode"] = ["1", "true", "yes"].contains(forceSlaveMode.lowercased())
    }

    return payload
  }
}
