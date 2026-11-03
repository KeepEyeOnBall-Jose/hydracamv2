// HydraCam patch: not part of upstream camera_android_camerax.
// See packages/camera_android_camerax/HYDRACAM_PATCH.md.

package io.flutter.plugins.camerax;

import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.TotalCaptureResult;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.camera.camera2.interop.Camera2CameraInfo;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.core.Camera;
import androidx.camera.core.Preview;
import androidx.camera.core.UseCase;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/**
 * Exposes the CameraX {@link Camera} bound by this plugin and the latest {@link
 * TotalCaptureResult} of its session so the host app can apply and verify Camera2 manual sensor
 * settings (exposure time, ISO) that the camera plugin API does not offer.
 */
@OptIn(markerClass = ExperimentalCamera2Interop.class)
public final class HydracamCaptureHooks {
  // Binding, configured session and result are one tuple guarded by this class.
  private static Camera boundCamera;
  private static String boundCameraId;
  private static PreviewObserver activeObserver;
  private static CameraCaptureSession activeSession;
  private static TotalCaptureResult latestCaptureResult;
  private static long graphEpoch;
  private static final Map<Preview, PreviewObserver> observers = new WeakHashMap<>();
  private static final Set<Preview> boundPreviews =
      Collections.newSetFromMap(new IdentityHashMap<>());
  private static final Set<CameraCaptureSession> retiredSessions =
      Collections.newSetFromMap(new WeakHashMap<>());

  private HydracamCaptureHooks() {}

  static final class PreviewObserver {
    private CameraCaptureSession configuredSession;
    private long configuredEpoch = -1;
    final CameraCaptureSession.CaptureCallback captureCallback =
        new CameraCaptureSession.CaptureCallback() {
          @Override
          public void onCaptureCompleted(
              @NonNull CameraCaptureSession session,
              @NonNull CaptureRequest request,
              @NonNull TotalCaptureResult result) {
            synchronized (HydracamCaptureHooks.class) {
              if (activeObserver == PreviewObserver.this
                  && activeSession == session
                  && !retiredSessions.contains(session)) {
                latestCaptureResult = result;
              }
            }
          }
        };
    final CameraCaptureSession.StateCallback stateCallback =
        new CameraCaptureSession.StateCallback() {
          @Override
          public void onConfigured(@NonNull CameraCaptureSession session) {
            synchronized (HydracamCaptureHooks.class) {
              if (retiredSessions.contains(session)) return;
              if (configuredSession != null && configuredSession != session) {
                retiredSessions.add(configuredSession);
              }
              if (activeObserver == PreviewObserver.this && activeSession != session) {
                clearActiveSession();
              }
              configuredSession = session;
              configuredEpoch = graphEpoch;
              activate(PreviewObserver.this);
            }
          }

          @Override
          public void onConfigureFailed(@NonNull CameraCaptureSession session) {
            onClosed(session);
          }

          @Override
          public void onClosed(@NonNull CameraCaptureSession session) {
            synchronized (HydracamCaptureHooks.class) {
              retiredSessions.add(session);
              if (configuredSession == session) configuredSession = null;
              if (activeObserver == PreviewObserver.this && activeSession == session) {
                clearActiveSession();
              }
            }
          }
        };
  }

  static PreviewObserver newPreviewObserver() {
    return new PreviewObserver();
  }

  static synchronized void registerPreview(Preview preview, PreviewObserver observer) {
    observers.put(preview, observer);
  }

  static synchronized void beforeGraphChange() {
    ++graphEpoch;
    for (PreviewObserver observer : observers.values()) {
      if (observer.configuredSession != null) retiredSessions.add(observer.configuredSession);
      observer.configuredSession = null;
      observer.configuredEpoch = -1;
    }
    clearActiveSession();
  }

  static synchronized void onUseCasesUnbound(List<? extends UseCase> useCases) {
    for (UseCase useCase : useCases) {
      if (useCase instanceof Preview) {
        boundPreviews.remove(useCase);
        if (observers.get(useCase) == activeObserver) clearActiveSession();
      }
    }
    // Retained Preview callbacks remain registered when only analysis/video
    // changes. Their next configured session can publish without replacement.
  }

  /** Camera returned by the most recent bindToLifecycle call, or null after unbindAll. */
  @Nullable
  public static synchronized Camera getBoundCamera() {
    return boundCamera;
  }

  /** Latest completed capture result of the bound camera session, if any. */
  @Nullable
  public static synchronized TotalCaptureResult getLatestCaptureResult() {
    return latestCaptureResult;
  }

  @Nullable
  public static synchronized TotalCaptureResult getLatestCaptureResult(
      @NonNull Camera expectedCamera) {
    return boundCamera == expectedCamera ? latestCaptureResult : null;
  }

  static synchronized void onCameraBound(
      @NonNull Camera camera, List<? extends UseCase> useCases) {
    boundCamera = camera;
    boundCameraId = Camera2CameraInfo.from(camera.getCameraInfo()).getCameraId();
    for (UseCase useCase : useCases) {
      if (useCase instanceof Preview) boundPreviews.add((Preview) useCase);
    }
    // onConfigured may arrive during bindToLifecycle, before this publication.
    for (Preview preview : boundPreviews) activate(observers.get(preview));
  }

  static synchronized void onCamerasUnbound() {
    beforeGraphChange();
    boundPreviews.clear();
    boundCamera = null;
    boundCameraId = null;
  }

  private static void activate(@Nullable PreviewObserver observer) {
    if (observer == null || boundCamera == null || observer.configuredSession == null
        || observer.configuredEpoch != graphEpoch
        || retiredSessions.contains(observer.configuredSession)) return;
    boolean bound = false;
    for (Preview preview : boundPreviews) {
      if (observers.get(preview) == observer) bound = true;
    }
    if (!bound || !observer.configuredSession.getDevice().getId().equals(boundCameraId)) return;
    if (activeSession != null && activeSession != observer.configuredSession) {
      retiredSessions.add(activeSession);
    }
    if (activeObserver != observer || activeSession != observer.configuredSession) {
      latestCaptureResult = null;
    }
    activeObserver = observer;
    activeSession = observer.configuredSession;
  }

  private static void clearActiveSession() {
    activeObserver = null;
    activeSession = null;
    latestCaptureResult = null;
  }
}
