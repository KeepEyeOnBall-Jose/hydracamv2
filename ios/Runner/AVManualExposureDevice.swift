import AVFoundation
import CoreMedia

/// The genuine iOS SDK boundary; ownership decisions remain in the controller.
final class AVManualExposureDevice: ManualExposureDevice {
  private let device: AVCaptureDevice

  init(_ device: AVCaptureDevice) { self.device = device }

  var uniqueID: String { device.uniqueID }
  var deviceTypeName: String { device.deviceType.rawValue }
  var activeFormat: ManualExposureFormat {
    let format = device.activeFormat
    return ManualExposureFormat(
      minExposureDuration: format.minExposureDuration,
      maxExposureDuration: format.maxExposureDuration,
      minISO: format.minISO,
      maxISO: format.maxISO
    )
  }
  var exposureMode: AVCaptureDevice.ExposureMode {
    get { device.exposureMode }
    set { device.exposureMode = newValue }
  }
  var whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode {
    get { device.whiteBalanceMode }
    set { device.whiteBalanceMode = newValue }
  }
  var focusMode: AVCaptureDevice.FocusMode {
    get { device.focusMode }
    set { device.focusMode = newValue }
  }
  var exposureDuration: CMTime { device.exposureDuration }
  var iso: Float { device.iso }
  var activeVideoMinFrameDuration: CMTime { device.activeVideoMinFrameDuration }
  var activeVideoMaxFrameDuration: CMTime { device.activeVideoMaxFrameDuration }
  var lensPosition: Float { device.lensPosition }

  func isExposureModeSupported(_ mode: AVCaptureDevice.ExposureMode) -> Bool {
    device.isExposureModeSupported(mode)
  }
  func isWhiteBalanceModeSupported(_ mode: AVCaptureDevice.WhiteBalanceMode) -> Bool {
    device.isWhiteBalanceModeSupported(mode)
  }
  func isFocusModeSupported(_ mode: AVCaptureDevice.FocusMode) -> Bool {
    device.isFocusModeSupported(mode)
  }
  func lockForConfiguration() throws { try device.lockForConfiguration() }
  func unlockForConfiguration() { device.unlockForConfiguration() }
  func setExposureModeCustom(
    duration: CMTime, iso: Float, completion: @escaping (CMTime) -> Void
  ) {
    device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: completion)
  }
}
