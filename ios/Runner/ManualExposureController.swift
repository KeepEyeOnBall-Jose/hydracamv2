import AVFoundation
import CoreMedia

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
      "manualLockActive": lockedUniqueID == device.uniqueID
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

