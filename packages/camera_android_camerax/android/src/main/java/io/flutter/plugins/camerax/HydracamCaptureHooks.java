// HydraCam patch: not part of upstream camera_android_camerax.
// See packages/camera_android_camerax/HYDRACAM_PATCH.md.

package io.flutter.plugins.camerax;

import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.TotalCaptureResult;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.Camera;
import androidx.camera.core.Preview;
import androidx.camera.core.UseCase;
import java.util.List;

/**
 * Exposes the CameraX {@link Camera} bound by this plugin and the latest {@link
 * TotalCaptureResult} of its session so the host app can apply and verify Camera2 manual sensor
 * settings (exposure time, ISO) that the camera plugin API does not offer.
 */
public final class HydracamCaptureHooks {
  private static volatile Camera boundCamera;
  private static volatile TotalCaptureResult latestCaptureResult;

  private static final CameraCaptureSession.CaptureCallback SESSION_CAPTURE_CALLBACK =
      new CameraCaptureSession.CaptureCallback() {
        @Override
        public void onCaptureCompleted(
            @NonNull CameraCaptureSession session,
            @NonNull CaptureRequest request,
            @NonNull TotalCaptureResult result) {
          latestCaptureResult = result;
        }
      };

  private HydracamCaptureHooks() {}

  static final class PreviewObserver {
    final CameraCaptureSession.CaptureCallback captureCallback = SESSION_CAPTURE_CALLBACK;
    final CameraCaptureSession.StateCallback stateCallback =
        new CameraCaptureSession.StateCallback() {
          @Override
          public void onConfigured(@NonNull CameraCaptureSession session) {}

          @Override
          public void onConfigureFailed(@NonNull CameraCaptureSession session) {}
        };
  }

  static PreviewObserver newPreviewObserver() {
    return new PreviewObserver();
  }

  static void registerPreview(Preview preview, PreviewObserver observer) {}

  static void beforeGraphChange() {}

  static void onUseCasesUnbound(List<? extends UseCase> useCases) {}

  /** Camera returned by the most recent bindToLifecycle call, or null after unbindAll. */
  @Nullable
  public static Camera getBoundCamera() {
    return boundCamera;
  }

  /** Latest completed capture result of the bound camera session, if any. */
  @Nullable
  public static TotalCaptureResult getLatestCaptureResult() {
    return latestCaptureResult;
  }

  @Nullable
  public static TotalCaptureResult getLatestCaptureResult(@NonNull Camera expectedCamera) {
    return getLatestCaptureResult();
  }

  static void onCameraBound(@NonNull Camera camera) {
    boundCamera = camera;
  }

  static void onCameraBound(@NonNull Camera camera, List<? extends UseCase> useCases) {
    onCameraBound(camera);
  }

  static void onCamerasUnbound() {
    boundCamera = null;
    latestCaptureResult = null;
  }

  @NonNull
  static CameraCaptureSession.CaptureCallback sessionCaptureCallback() {
    return SESSION_CAPTURE_CALLBACK;
  }
}
