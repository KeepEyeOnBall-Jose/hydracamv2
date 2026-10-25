package io.flutter.plugins.camerax;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.when;

import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.TotalCaptureResult;
import androidx.camera.camera2.impl.Camera2ImplConfig;
import androidx.camera.camera2.interop.Camera2CameraInfo;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraInfo;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.Preview;
import androidx.camera.core.UseCase;
import androidx.camera.video.VideoCapture;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.lifecycle.LifecycleOwner;
import java.util.Arrays;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.MockedStatic;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/** Exercises the callbacks installed by the actual Preview and provider proxy APIs. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class HydracamCaptureHooksTest {
  private MockedStatic<Camera2CameraInfo> cameraInfos;
  private PreviewProxyApi previewApi;
  private ProcessCameraProviderProxyApi providerApi;
  private ProcessCameraProvider provider;
  private LifecycleOwner lifecycle;
  private CameraSelector selector;
  private Camera camera;

  @Before
  public void setUp() {
    HydracamCaptureHooks.onCamerasUnbound();
    cameraInfos = mockStatic(Camera2CameraInfo.class);
    final ProxyApiRegistrar registrar = mock(ProxyApiRegistrar.class);
    lifecycle = mock(LifecycleOwner.class);
    when(registrar.getLifecycleOwner()).thenReturn(lifecycle);
    previewApi = new PreviewProxyApi(registrar);
    providerApi = new ProcessCameraProviderProxyApi(registrar);
    provider = mock(ProcessCameraProvider.class);
    selector = mock(CameraSelector.class);
    camera = camera("0");
  }

  @After
  public void tearDown() {
    HydracamCaptureHooks.onCamerasUnbound();
    if (cameraInfos != null) cameraInfos.close();
  }

  @Test
  public void configuredPreviewPublishesItsCurrentResult() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession session = session("0");
    preview.state.onConfigured(session);
    final TotalCaptureResult result = result(preview, session);
    assertSame(camera, HydracamCaptureHooks.getBoundCamera());
    assertSame(result, HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void retainedPreviewStillPublishesAfterAnalysisUnbindAndVideoBind() {
    final ObservedPreview preview = preview();
    final ImageAnalysis analysis = mock(ImageAnalysis.class);
    bind(camera, preview.preview, analysis);
    final CameraCaptureSession initial = session("0");
    preview.state.onConfigured(initial);
    result(preview, initial);
    providerApi.unbind(provider, Arrays.asList(analysis));
    bind(camera, mock(VideoCapture.class));
    final CameraCaptureSession recording = session("0");
    preview.state.onConfigured(recording);
    final TotalCaptureResult result = result(preview, recording);
    assertSame(result, HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void oldSessionResultCannotReplaceTheNewSessionResult() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession old = session("0");
    preview.state.onConfigured(old);
    result(preview, old);
    bind(camera, mock(VideoCapture.class));
    final CameraCaptureSession current = session("0");
    preview.state.onConfigured(current);
    final TotalCaptureResult result = result(preview, current);
    result(preview, old);
    assertSame(result, HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void oldSessionCloseCannotClearTheNewSessionResult() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession old = session("0");
    preview.state.onConfigured(old);
    bind(camera, mock(VideoCapture.class));
    final CameraCaptureSession current = session("0");
    preview.state.onConfigured(current);
    final TotalCaptureResult result = result(preview, current);
    preview.state.onClosed(old);
    assertSame(result, HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void wrongCameraSessionCannotPublishAResult() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession wrong = session("1");
    preview.state.onConfigured(wrong);
    result(preview, wrong);
    assertNull(HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void fullUnbindRejectsLateResultsFromTheOldPreview() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession session = session("0");
    preview.state.onConfigured(session);
    result(preview, session);
    providerApi.unbindAll(provider);
    result(preview, session);
    assertNull(HydracamCaptureHooks.getBoundCamera());
    assertNull(HydracamCaptureHooks.getLatestCaptureResult());
  }

  @Test
  public void oldPreviewCannotPublishIntoAReplacementPreviewOnTheSameCamera() {
    final ObservedPreview old = preview();
    bind(camera, old.preview);
    final CameraCaptureSession oldSession = session("0");
    old.state.onConfigured(oldSession);
    providerApi.unbindAll(provider);
    final ObservedPreview current = preview();
    bind(camera, current.preview);
    final CameraCaptureSession currentSession = session("0");
    current.state.onConfigured(currentSession);
    final TotalCaptureResult result = result(current, currentSession);
    old.state.onConfigured(oldSession);
    result(old, oldSession);
    old.state.onClosed(oldSession);
    assertSame(result, HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void expectedCameraLookupCannotRelabelAnotherBoundCamerasResult() {
    final ObservedPreview old = preview();
    bind(camera, old.preview);
    providerApi.unbindAll(provider);
    final Camera replacement = camera("1");
    final ObservedPreview current = preview();
    bind(replacement, current.preview);
    final CameraCaptureSession session = session("1");
    current.state.onConfigured(session);
    final TotalCaptureResult result = result(current, session);
    assertNull(HydracamCaptureHooks.getLatestCaptureResult(camera));
    assertSame(result, HydracamCaptureHooks.getLatestCaptureResult(replacement));
  }

  @Test
  public void graphChangeRequiresAResultFromTheNewConfiguredSession() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession old = session("0");
    preview.state.onConfigured(old);
    result(preview, old);
    bind(camera, mock(VideoCapture.class));
    result(preview, old);
    assertNull(HydracamCaptureHooks.getLatestCaptureResult(camera));
    final CameraCaptureSession current = session("0");
    preview.state.onConfigured(current);
    assertSame(result(preview, current), HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  @Test
  public void unbindingPreviewRejectsItsLateResults() {
    final ObservedPreview preview = preview();
    bind(camera, preview.preview);
    final CameraCaptureSession session = session("0");
    preview.state.onConfigured(session);
    result(preview, session);
    providerApi.unbind(provider, Arrays.asList(preview.preview));
    result(preview, session);
    assertNull(HydracamCaptureHooks.getLatestCaptureResult(camera));
  }

  private Camera camera(String cameraId) {
    final Camera camera = mock(Camera.class);
    final CameraInfo info = mock(CameraInfo.class);
    final Camera2CameraInfo camera2Info = mock(Camera2CameraInfo.class);
    when(camera.getCameraInfo()).thenReturn(info);
    when(camera2Info.getCameraId()).thenReturn(cameraId);
    cameraInfos.when(() -> Camera2CameraInfo.from(info)).thenReturn(camera2Info);
    return camera;
  }

  private void bind(Camera camera, UseCase... useCases) {
    when(provider.bindToLifecycle(eq(lifecycle), eq(selector), any(UseCase[].class)))
        .thenReturn(camera);
    providerApi.bindToLifecycle(provider, selector, Arrays.asList(useCases));
  }

  private ObservedPreview preview() {
    final Preview preview = previewApi.pigeon_defaultConstructor(null, null, null);
    final Camera2ImplConfig config = new Camera2ImplConfig(preview.getCurrentConfig());
    final CameraCaptureSession.CaptureCallback capture = config.getSessionCaptureCallback(null);
    final CameraCaptureSession.StateCallback state = config.getSessionStateCallback(null);
    assertNotNull(capture);
    assertNotNull(state);
    return new ObservedPreview(preview, capture, state);
  }

  private CameraCaptureSession session(String cameraId) {
    final CameraCaptureSession session = mock(CameraCaptureSession.class);
    final CameraDevice device = mock(CameraDevice.class);
    when(device.getId()).thenReturn(cameraId);
    when(session.getDevice()).thenReturn(device);
    return session;
  }

  private TotalCaptureResult result(ObservedPreview preview, CameraCaptureSession session) {
    final TotalCaptureResult result = mock(TotalCaptureResult.class);
    preview.capture.onCaptureCompleted(session, mock(CaptureRequest.class), result);
    return result;
  }

  private static final class ObservedPreview {
    final Preview preview;
    final CameraCaptureSession.CaptureCallback capture;
    final CameraCaptureSession.StateCallback state;

    ObservedPreview(Preview preview, CameraCaptureSession.CaptureCallback capture,
        CameraCaptureSession.StateCallback state) {
      this.preview = preview;
      this.capture = capture;
      this.state = state;
    }
  }
}
