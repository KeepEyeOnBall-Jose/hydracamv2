import AVFoundation
import CoreMedia
import XCTest
@testable import ManualExposure

final class ManualExposureControllerTests: XCTestCase {
  private let camera = TestExposureDevice(uniqueID: "original-camera")
  private let otherCamera = TestExposureDevice(uniqueID: "other-camera")

  private func controller() -> ManualExposureController {
    let devices = [camera.uniqueID: camera, otherCamera.uniqueID: otherCamera]
    return ManualExposureController(resolveDevice: { devices[$0] })
  }

  private func apply(
    _ controller: ManualExposureController,
    ownerId: String = "recording-A",
    cameraName: String = "original-camera",
    shutter: Int64 = 16_666_667
  ) -> [String: Any?] {
    var response: [String: Any?]?
    controller.applyLock(
      ownerId: ownerId,
      cameraName: cameraName,
      exposureTimeNs: shutter,
      frameDurationNs: 33_333_333
    ) { response = $0 }
    XCTAssertNotNil(response)
    return response ?? [:]
  }

  func testFailedRestorationRetainsOwnerWithoutUnlockingAnUnacquiredDevice() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    let unlocksBeforeFailure = camera.unlockCount
    camera.failConfigurationLock = true

    let result = controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)

    XCTAssertEqual(result["status"] as? String, "error")
    XCTAssertEqual(camera.unlockCount, unlocksBeforeFailure)
    XCTAssertEqual(camera.exposureMode, .custom)
    XCTAssertEqual(
      controller.readCaptureSettings(cameraName: camera.uniqueID)["manualLockActive"] as? Bool,
      true
    )
  }

  func testRestorationRetryRestoresOriginalModesAndClearsOwnership() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    camera.failConfigurationLock = true
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "error")
    camera.failConfigurationLock = false

    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
    XCTAssertEqual(camera.whiteBalanceMode, .autoWhiteBalance)
    XCTAssertEqual(camera.focusMode, .autoFocus)
    XCTAssertEqual(
      controller.readCaptureSettings(cameraName: camera.uniqueID)["manualLockActive"] as? Bool,
      false
    )
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
  }

  func testWrongDeviceCannotDiscardTheOriginalRestoration() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")

    XCTAssertEqual(
      controller.release(ownerId: "recording-A", cameraName: otherCamera.uniqueID)["status"] as? String,
      "not_locked"
    )
    XCTAssertEqual(otherCamera.unlockCount, 0)
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
    XCTAssertEqual(camera.whiteBalanceMode, .autoWhiteBalance)
    XCTAssertEqual(camera.focusMode, .autoFocus)
  }

  func testNewManualLockCannotOverwriteUnresolvedRestoration() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    camera.failConfigurationLock = true
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "error")
    camera.failConfigurationLock = false

    XCTAssertEqual(apply(controller, shutter: 8_333_333)["status"] as? String, "busy")
    XCTAssertEqual(apply(controller, ownerId: "recording-B", cameraName: otherCamera.uniqueID)["status"] as? String, "busy")
    XCTAssertEqual(otherCamera.exposureMode, .autoExpose)
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
    XCTAssertEqual(camera.whiteBalanceMode, .autoWhiteBalance)
    XCTAssertEqual(camera.focusMode, .autoFocus)
  }

  func testSameOwnerRelockPreservesTheOriginalAutoModes() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
    XCTAssertEqual(camera.whiteBalanceMode, .autoWhiteBalance)
    XCTAssertEqual(camera.focusMode, .autoFocus)
  }

  func testAnotherOwnerCannotReplaceOrReleaseTheCurrentOwner() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    let conflict = apply(controller, ownerId: "recording-B")
    XCTAssertEqual(conflict["status"] as? String, "busy")
    XCTAssertEqual(conflict["cleanupRequired"] as? Bool, false)
    XCTAssertEqual(controller.release(ownerId: "recording-B", cameraName: camera.uniqueID)["status"] as? String, "not_locked")
    XCTAssertEqual(camera.exposureMode, .custom)
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(apply(controller, ownerId: "recording-B")["status"] as? String, "locked")
    XCTAssertEqual(controller.release(ownerId: "recording-B", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
  }

  func testReleaseUsesTheOriginalDeviceWhenLookupChanges() {
    let replacement = TestExposureDevice(uniqueID: camera.uniqueID)
    var resolved = camera
    let controller = ManualExposureController(resolveDevice: { _ in resolved })
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    resolved = replacement

    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
    XCTAssertEqual(camera.whiteBalanceMode, .autoWhiteBalance)
    XCTAssertEqual(camera.focusMode, .autoFocus)
    XCTAssertEqual(replacement.unlockCount, 0)
  }

  func testOwnershipIsReservedWhileNativeExposureCompletionIsPending() {
    let controller = controller()
    camera.holdExposureCompletion = true
    var initialResponse: [String: Any?]?
    controller.applyLock(ownerId: "recording-A", cameraName: camera.uniqueID,
      exposureTimeNs: 16_666_667, frameDurationNs: 33_333_333) { initialResponse = $0 }
    XCTAssertNil(initialResponse)
    XCTAssertEqual(apply(controller, ownerId: "recording-B")["status"] as? String, "busy")
    camera.completeExposure()
    XCTAssertEqual(initialResponse?["status"] as? String, "locked")
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
  }

  func testFailedRelockAcknowledgesTheExistingCleanupOwner() {
    let controller = controller()
    XCTAssertEqual(apply(controller)["status"] as? String, "locked")
    camera.failConfigurationLock = true

    let result = apply(controller)

    XCTAssertEqual(result["status"] as? String, "error")
    XCTAssertEqual(result["cleanupRequired"] as? Bool, true)
    camera.failConfigurationLock = false
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
  }

  func testRestorationWaitsForPendingNativeExposureCompletion() {
    let controller = controller()
    camera.holdExposureCompletion = true
    var response: [String: Any?]?
    controller.applyLock(ownerId: "recording-A", cameraName: camera.uniqueID,
      exposureTimeNs: 16_666_667, frameDurationNs: 33_333_333) { response = $0 }

    let pendingRelease = controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)

    XCTAssertEqual(pendingRelease["status"] as? String, "busy")
    XCTAssertEqual(pendingRelease["cleanupRequired"] as? Bool, true)
    XCTAssertEqual(camera.exposureMode, .custom)
    XCTAssertEqual(apply(controller, ownerId: "recording-B")["status"] as? String, "busy")
    camera.completeExposure()
    XCTAssertNotNil(response)
    XCTAssertEqual(controller.release(ownerId: "recording-A", cameraName: camera.uniqueID)["status"] as? String, "released")
    XCTAssertEqual(camera.exposureMode, .autoExpose)
    XCTAssertEqual(camera.whiteBalanceMode, .autoWhiteBalance)
    XCTAssertEqual(camera.focusMode, .autoFocus)
  }
}

/// The external camera boundary only; all ownership decisions run in the
/// production controller compiled by this package.
private final class TestExposureDevice: ManualExposureDevice {
  enum ConfigurationFailure: Error { case busy }

  init(uniqueID: String) { self.uniqueID = uniqueID }

  let uniqueID: String
  let deviceTypeName = "test-device-boundary"
  let activeFormat = ManualExposureFormat(
    minExposureDuration: CMTime(value: 1, timescale: 10_000),
    maxExposureDuration: CMTime(value: 1, timescale: 1),
    minISO: 50,
    maxISO: 3_200
  )
  var exposureMode: AVCaptureDevice.ExposureMode = .autoExpose
  var whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .autoWhiteBalance
  var focusMode: AVCaptureDevice.FocusMode = .autoFocus
  var exposureDuration = CMTime(value: 1, timescale: 30)
  var iso: Float = 200
  var activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
  var activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
  var lensPosition: Float = 0.5
  var failConfigurationLock = false
  private(set) var unlockCount = 0
  var holdExposureCompletion = false
  private var exposureCompletion: ((CMTime) -> Void)?

  func completeExposure() {
    let completion = exposureCompletion
    exposureCompletion = nil
    completion?(.zero)
  }

  func isExposureModeSupported(_ mode: AVCaptureDevice.ExposureMode) -> Bool { true }
  func isWhiteBalanceModeSupported(_ mode: AVCaptureDevice.WhiteBalanceMode) -> Bool { true }
  func isFocusModeSupported(_ mode: AVCaptureDevice.FocusMode) -> Bool { true }

  func lockForConfiguration() throws {
    if failConfigurationLock { throw ConfigurationFailure.busy }
  }

  func unlockForConfiguration() { unlockCount += 1 }

  func setExposureModeCustom(
    duration: CMTime,
    iso: Float,
    completion: @escaping (CMTime) -> Void
  ) {
    exposureMode = .custom
    exposureDuration = duration
    self.iso = iso
    if holdExposureCompletion {
      exposureCompletion = completion
    } else {
      completion(.zero)
    }
  }
}
