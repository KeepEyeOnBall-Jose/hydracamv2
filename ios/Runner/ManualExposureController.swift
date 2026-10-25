import AVFoundation
import CoreMedia
import Foundation

/// Values needed from the native format, without retaining an SDK format object.
struct ManualExposureFormat {
  let minExposureDuration: CMTime
  let maxExposureDuration: CMTime
  let minISO: Float
  let maxISO: Float
}

/// External camera operations used by the production exposure controller.
protocol ManualExposureDevice: AnyObject {
  var uniqueID: String { get }
  var deviceTypeName: String { get }
  var activeFormat: ManualExposureFormat { get }
  var exposureMode: AVCaptureDevice.ExposureMode { get set }
  var whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode { get set }
  var focusMode: AVCaptureDevice.FocusMode { get set }
  var exposureDuration: CMTime { get }
  var iso: Float { get }
  var activeVideoMinFrameDuration: CMTime { get }
  var activeVideoMaxFrameDuration: CMTime { get }
  var lensPosition: Float { get }
  func isExposureModeSupported(_ mode: AVCaptureDevice.ExposureMode) -> Bool
  func isWhiteBalanceModeSupported(_ mode: AVCaptureDevice.WhiteBalanceMode) -> Bool
  func isFocusModeSupported(_ mode: AVCaptureDevice.FocusMode) -> Bool
  func lockForConfiguration() throws
  func unlockForConfiguration()
  func setExposureModeCustom(
    duration: CMTime, iso: Float, completion: @escaping (CMTime) -> Void
  )
}

/// Locks shutter (exposure duration), ISO, white balance and focus on the
/// AVCaptureDevice the camera plugin opened (its uniqueID is the Flutter
/// camera name). ISO is metered once from running auto exposure (shutter
/// priority) and then held. iOS does not report rolling-shutter readout time.
final class ManualExposureController {
  private let deviceResolver: (String) -> ManualExposureDevice?

  init(resolveDevice: @escaping (String) -> ManualExposureDevice?) {
    deviceResolver = resolveDevice
  }

  private struct PreviousModes {
    let exposure: AVCaptureDevice.ExposureMode
    let whiteBalance: AVCaptureDevice.WhiteBalanceMode
    let focus: AVCaptureDevice.FocusMode
  }

  /// A recording owns its original device and modes until restoration succeeds.
  private final class Lease {
    let ownerId: String
    let device: ManualExposureDevice
    let previousModes: PreviousModes
    var request: [String: Any?]
    var pendingApplies = 0
    var restorationRequested = false

    init(ownerId: String, device: ManualExposureDevice, request: [String: Any?]) {
      self.ownerId = ownerId
      self.device = device
      self.request = request
      previousModes = PreviousModes(
        exposure: device.exposureMode,
        whiteBalance: device.whiteBalanceMode,
        focus: device.focusMode
      )
    }
  }

  private var lease: Lease?

  func applyLock(
    ownerId: String,
    cameraName: String?,
    exposureTimeNs: Int64,
    frameDurationNs: Int64,
    completion: @escaping ([String: Any?]) -> Void
  ) {
    let device: ManualExposureDevice
    if let active = lease {
      guard active.ownerId == ownerId, active.device.uniqueID == cameraName else {
        completion(["status": "busy", "cleanupRequired": false])
        return
      }
      guard !active.restorationRequested, active.pendingApplies == 0 else {
        completion(["status": "busy", "cleanupRequired": true])
        return
      }
      device = active.device
    } else {
      guard let resolved = resolveDevice(cameraName) else {
        completion(["status": "no_camera", "cleanupRequired": false])
        return
      }
      device = resolved
    }
    guard device.isExposureModeSupported(.custom) else {
      completion([
        "status": "unsupported", "cameraId": device.uniqueID,
        "cleanupRequired": lease != nil
      ])
      return
    }
    let format = device.activeFormat
    let request: [String: Any?]
    if let active = lease,
       (active.request["requestedExposureTimeNs"] as? Int64) == exposureTimeNs {
      request = active.request
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
        "status": "error", "cameraId": device.uniqueID,
        "error": error.localizedDescription, "cleanupRequired": lease != nil
      ])
      return
    }
    defer { device.unlockForConfiguration() }
    // Reserve ownership before any mutation or asynchronous SDK acknowledgement.
    let active = lease ?? Lease(ownerId: ownerId, device: device, request: request)
    lease = active
    active.request = request
    active.pendingApplies += 1
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
      let acknowledge = {
        active.pendingApplies -= 1
        guard self.lease === active else {
          completion(["status": "error", "cleanupRequired": false])
          return
        }
        completion(request.merging([
          "status": active.restorationRequested ? "busy" : "locked",
          "cameraId": device.uniqueID, "cleanupRequired": true
        ]) { _, new in new })
      }
      // Flutter channel calls are on main; native completion can use another queue.
      if Thread.isMainThread {
        acknowledge()
      } else {
        DispatchQueue.main.async(execute: acknowledge)
      }
    }
  }

  func release(ownerId: String, cameraName: String?) -> [String: Any?] {
    guard let active = lease else {
      return ["status": "released", "cleanupRequired": false]
    }
    guard active.ownerId == ownerId, active.device.uniqueID == cameraName else {
      return ["status": "not_locked", "cleanupRequired": false]
    }
    active.restorationRequested = true
    guard active.pendingApplies == 0 else {
      return ["status": "busy", "cleanupRequired": true]
    }
    let device = active.device
    do {
      try device.lockForConfiguration()
    } catch {
      return [
        "status": "error", "cameraId": device.uniqueID,
        "error": error.localizedDescription, "cleanupRequired": true
      ]
    }
    defer { device.unlockForConfiguration() }
    let modes = active.previousModes
    guard device.isExposureModeSupported(modes.exposure),
          device.isWhiteBalanceModeSupported(modes.whiteBalance),
          device.isFocusModeSupported(modes.focus) else {
      return [
        "status": "error", "cameraId": device.uniqueID,
        "error": "Original camera modes are unavailable", "cleanupRequired": true
      ]
    }
    device.exposureMode = modes.exposure
    device.whiteBalanceMode = modes.whiteBalance
    device.focusMode = modes.focus
    lease = nil
    return ["status": "released", "cameraId": device.uniqueID, "cleanupRequired": false]
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
      "deviceType": device.deviceTypeName,
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
      "manualLockActive": lease?.device.uniqueID == device.uniqueID
    ]
  }

  private func meterLockRequest(
    device: ManualExposureDevice,
    format: ManualExposureFormat,
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

  private func resolveDevice(_ cameraName: String?) -> ManualExposureDevice? {
    guard let cameraName, !cameraName.isEmpty else {
      return nil
    }
    return deviceResolver(cameraName)
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

