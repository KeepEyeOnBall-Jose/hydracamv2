import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/camera_capture_settings.dart";
import "package:hydracam/services/camera_compatibility_policy.dart";

void main() {
  group("CameraCompatibilityPolicyResolver.fromDeviceInfo", () {
    test("returns the none policy when device info is null", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(null);

      expect(policy, same(CameraCompatibilityPolicy.none));
      expect(policy.isActive, isFalse);
      expect(policy.profileOverride, isNull);
      expect(policy.usePresetDefaultFps, isFalse);
      expect(policy.retryTimedOutPhotoAfterReinitialize, isFalse);
      expect(policy.reason, isNull);
    });

    test("returns the none policy for a non-Samsung device", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"manufacturer": "Google", "model": "Pixel 7"},
      );

      expect(policy.isActive, isFalse);
      expect(policy.profileOverride, isNull);
      expect(policy.reason, isNull);
    });

    test("activates the S7 edge policy for Samsung SM-G935 devices", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"manufacturer": "Samsung", "model": "SM-G935F"},
      );

      expect(policy.isActive, isTrue);
      expect(policy.usePresetDefaultFps, isTrue);
      expect(policy.retryTimedOutPhotoAfterReinitialize, isTrue);
      expect(policy.profileOverride, isNull);
      expect(policy.reason, isNotNull);
      expect(policy.reason, isNotEmpty);
    });

    test("detects the SAMSUNG-SM-G935 model variant", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"manufacturer": "Samsung", "model": "SAMSUNG-SM-G935A"},
      );

      expect(policy.isActive, isTrue);
      expect(policy.usePresetDefaultFps, isTrue);
      expect(policy.retryTimedOutPhotoAfterReinitialize, isTrue);
    });

    test("uses the brand field as a fallback when manufacturer is absent", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"brand": "Samsung", "model": "SM-G935F"},
      );

      expect(policy.isActive, isTrue);
      expect(policy.usePresetDefaultFps, isTrue);
    });

    test("matches manufacturer and model case-insensitively", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"manufacturer": "SAMSUNG", "model": "sm-g935f"},
      );

      expect(policy.isActive, isTrue);
      expect(policy.usePresetDefaultFps, isTrue);
    });

    test("does not activate when the manufacturer is Samsung but model differs",
        () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"manufacturer": "Samsung", "model": "SM-G960F"},
      );

      expect(policy.isActive, isFalse);
    });
  });

  group("CameraCompatibilityPolicy.isActive", () {
    test("is true for the resolved Samsung S7 edge policy", () {
      final policy = CameraCompatibilityPolicyResolver.fromDeviceInfo(
        const {"manufacturer": "Samsung", "model": "SM-G935F"},
      );

      expect(policy.isActive, isTrue);
    });

    test("is false for the none policy and other devices", () {
      expect(CameraCompatibilityPolicy.none.isActive, isFalse);
      expect(
        CameraCompatibilityPolicyResolver.fromDeviceInfo(
          const {"manufacturer": "Apple", "model": "iPhone15,2"},
        ).isActive,
        isFalse,
      );
    });
  });

  group("CameraCompatibilityPolicy.resolveProfile", () {
    test("returns the profile override when the policy sets one", () {
      const policy = CameraCompatibilityPolicy(
        profileOverride: VideoCaptureProfile.detail4k30,
      );

      expect(
        policy.resolveProfile(VideoCaptureProfile.sport1080p60),
        VideoCaptureProfile.detail4k30,
      );
    });

    test("returns the requested profile unchanged when no override is set", () {
      expect(
        CameraCompatibilityPolicy.none
            .resolveProfile(VideoCaptureProfile.sport1080p60),
        VideoCaptureProfile.sport1080p60,
      );
    });
  });
}
