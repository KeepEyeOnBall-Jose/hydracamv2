import "dart:async";
import "dart:io";

// ignore: depend_on_referenced_packages
import "package:camera_platform_interface/camera_platform_interface.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/camera_capture_settings.dart";
import "package:hydracam/services/camera_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../test_utils/mock_services.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform originalPlatform;
  late MockStorageService storageService;
  final _TestPathProviderPlatform pathProvider = _TestPathProviderPlatform();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    SharedPreferences.setMockInitialValues({});
    storageService = MockStorageService();
    when(() => storageService.isRecordingBlocked).thenReturn(false);
    when(() => storageService.dispose()).thenReturn(null);
    LogService.instance.clearLogs();
  });

  tearDown(() {
    CameraPlatform.instance = originalPlatform;
    LogService.instance.clearLogs();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  test("takePhoto surfaces camera failures instead of returning a fake path",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform(cameras: const []);
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await expectLater(
      cameraService.takePhoto(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("No cameras available"),
        ),
      ),
    );
  });

  test("startRecordingVideo stays inactive when the camera platform fails",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform(
      startRecordingError: PlatformException(
        code: "ios_camera_start_failed",
        message: "Simulated iPad recording start failure",
      ),
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await expectLater(
      cameraService.startRecordingVideo(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("Simulated iPad recording start failure"),
        ),
      ),
    );

    expect(cameraService.isRecording, isFalse);
  });

  test("startRecordingVideo works when the iPad has no flash capability",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform(
      setFlashModeError: PlatformException(
        code: "setFlashModeFailed",
        message: "Device does not have flash capabilities",
      ),
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.startRecordingVideo();

    expect(cameraService.isRecording, isTrue);
    expect(
      LogService.instance.logs.any((entry) =>
          entry["message"].toString().contains("Flash is unavailable")),
      isTrue,
    );
  });

  test("non-flash initialization failures still surface", () async {
    CameraPlatform.instance = _FakeCameraPlatform(
      setFlashModeError: PlatformException(
        code: "setFlashModeFailed",
        message: "Camera session is unavailable",
      ),
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await expectLater(
      cameraService.ensureCameraIsReady(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("Camera session is unavailable"),
        ),
      ),
    );
  });

  test("stopRecordingVideo surfaces the camera plugin no-recording error",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform();
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.ensureCameraIsReady();

    await expectLater(
      cameraService.stopRecordingVideo(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("stopVideoRecording was called when no video is recording"),
        ),
      ),
    );

    expect(cameraService.isRecording, isFalse);
  });

  test("mock camera writes placeholder media without a platform camera",
      () async {
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );

    await cameraService.initAvailableCameras();
    final photoPath = await cameraService.takePhoto();
    await cameraService.startRecordingVideo();
    final videoPath = await cameraService.stopRecordingVideo();

    expect(cameraService.isUsingMockCamera, isTrue);
    expect(cameraService.controller, isNull);
    expect(cameraService.deviceCameras, hasLength(1));
    expect(File(photoPath).existsSync(), isTrue);
    expect(File(videoPath).existsSync(), isTrue);
    expect(cameraService.isRecording, isFalse);
  });

  test("selected ultra-wide lens uses sport 1080p60 controller settings",
      () async {
    final fakePlatform = _FakeCameraPlatform(
      cameras: const [
        CameraDescription(
          name: "iphone-wide",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.wide,
        ),
        CameraDescription(
          name: "iphone-ultra-wide",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.ultraWide,
        ),
      ],
    );
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "cameraLensPreference": LensPreference.ultraWide.storageValue,
      "videoCaptureProfile": VideoCaptureProfile.sport1080p60.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.startRecordingVideo();

    expect(fakePlatform.lastCreatedCamera?.name, "iphone-ultra-wide");
    expect(
      fakePlatform.lastMediaSettings?.resolutionPreset,
      ResolutionPreset.veryHigh,
    );
    expect(fakePlatform.lastMediaSettings?.fps, 60);
  });

  test("changing video profile preserves the selected camera", () async {
    final fakePlatform = _FakeCameraPlatform(
      cameras: const [
        CameraDescription(
          name: "iphone-wide",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.wide,
        ),
        CameraDescription(
          name: "iphone-telephoto",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.telephoto,
        ),
      ],
    );
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "selectedCameraName": "iphone-telephoto",
      "videoCaptureProfile": VideoCaptureProfile.standard1080p30.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.ensureCameraIsReady();
    await cameraService.setVideoCaptureProfile(VideoCaptureProfile.detail4k30);

    expect(fakePlatform.lastCreatedCamera?.name, "iphone-telephoto");
    expect(
      fakePlatform.lastMediaSettings?.resolutionPreset,
      ResolutionPreset.ultraHigh,
    );
    expect(fakePlatform.lastMediaSettings?.fps, 30);
  });

  test("macOS runtime uses the real camera backend unless mock is explicit",
      () async {
    final cameraService = CameraService(storageService: storageService);

    expect(cameraService.isUsingMockCamera, isFalse);
  });
}

class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({
    List<CameraDescription>? cameras,
    this.startRecordingError,
    this.setFlashModeError,
  }) : cameras = cameras ??
            const [
              CameraDescription(
                name: "fake-back-camera",
                lensDirection: CameraLensDirection.back,
                sensorOrientation: 90,
              ),
            ];

  final List<CameraDescription> cameras;
  final PlatformException? startRecordingError;
  final PlatformException? setFlashModeError;
  final StreamController<CameraErrorEvent> _errorController =
      StreamController<CameraErrorEvent>.broadcast();
  CameraDescription? lastCreatedCamera;
  MediaSettings? lastMediaSettings;

  bool _isRecording = false;
  int _nextCameraId = 1;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    lastCreatedCamera = cameraDescription;
    lastMediaSettings = mediaSettings;
    return _nextCameraId++;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream<CameraInitializedEvent>.value(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream<CameraClosingEvent>.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errorController.stream;

  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(
          int cameraId) =>
      const Stream<CameraResolutionChangedEvent>.empty();

  @override
  Stream<VideoRecordedEvent> onVideoRecordedEvent(int cameraId) =>
      const Stream<VideoRecordedEvent>.empty();

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    final error = setFlashModeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    final error = startRecordingError;
    if (error != null) {
      throw error;
    }
    _isRecording = true;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    if (!_isRecording) {
      throw PlatformException(
        code: "No video is recording",
        message: "stopVideoRecording was called when no video is recording.",
      );
    }
    _isRecording = false;
    return XFile("unused-video.mp4");
  }

  @override
  Future<XFile> takePicture(int cameraId) async => XFile("unused-photo.jpg");

  @override
  Future<void> dispose(int cameraId) async {}
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("camera_service_mock_docs");
    return _documentsDir!.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
