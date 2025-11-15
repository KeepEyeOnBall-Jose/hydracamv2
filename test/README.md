# HydraCam Test Suite

This directory contains comprehensive tests for the HydraCam application, organized in a TDD (Test-Driven Development) style to ensure the app works correctly across Android, iOS, and desktop platforms.

## Test Structure

```
test/
├── test_utils/              # Shared test utilities
│   ├── mock_services.dart   # Mock and fake service implementations
│   └── widget_test_helpers.dart  # Widget testing helpers
├── services/                # Unit tests for services
│   ├── camera_service_test.dart
│   ├── storage_service_test.dart
│   └── session_manager_test.dart
├── widgets/                 # Widget tests for UI components
│   └── slave_screen_test.dart
├── flows/                   # Integration-style flow tests
│   ├── camera_capture_flow_test.dart
│   └── session_creation_flow_test.dart
├── platform/                # Platform-specific behavior tests
│   └── platform_behavior_test.dart
└── widget_test.dart         # Main app smoke test
```

## Test Categories

### 1. Unit Tests (`test/services/`)

Test individual service classes in isolation:

- **camera_service_test.dart**: Camera initialization, photo capture, video recording logic
- **storage_service_test.dart**: Storage threshold detection, recording block behavior
- **session_manager_test.dart**: Session lifecycle, media management

These tests use mocks to isolate the service under test from its dependencies.

### 2. Widget Tests (`test/widgets/`)

Test UI components and their interaction with services:

- **slave_screen_test.dart**: Slave device UI, camera controls, storage warnings

Widget tests pump the widget tree and verify UI elements appear correctly and respond to user interactions.

### 3. Flow Tests (`test/flows/`)

Test end-to-end scenarios across multiple components:

- **camera_capture_flow_test.dart**: Complete photo/video capture workflow
- **session_creation_flow_test.dart**: Session creation, management, and ending

Flow tests verify that components work together correctly for real user workflows.

### 4. Platform Tests (`test/platform/`)

Document and test platform-specific behavior:

- **platform_behavior_test.dart**: Mobile vs desktop feature differences

## Running Tests

### Run all tests
```bash
flutter test
```

### Run specific test file
```bash
flutter test test/services/camera_service_test.dart
```

### Run tests with coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Run tests in verbose mode
```bash
flutter test --reporter expanded
```

## Test Philosophy

### TDD Approach

1. **Write tests first** for new features
2. **Watch them fail** to ensure they test the right thing
3. **Implement the feature** to make tests pass
4. **Refactor** while keeping tests green

### Testing Pyramid

- **Many unit tests**: Fast, focused, test individual functions
- **Some widget tests**: Test UI components and interactions
- **Few flow tests**: Test complete user workflows

### Platform Testing Strategy

Since Flutter runs on multiple platforms with different capabilities:

- **Use dependency injection** to mock platform-specific APIs
- **Abstract platform checks** behind testable interfaces
- **Document platform differences** in tests
- **Test business logic** independently of platform

## Key Testing Patterns

### Mocking with Mocktail

```dart
import "package:mocktail/mocktail.dart";

class MockCameraService extends Mock implements CameraService {}

// In test:
final mockCamera = MockCameraService();
when(() => mockCamera.takePhoto()).thenAnswer((_) async => "/path/to/photo.jpg");
```

### Faking Simple Services

```dart
class FakeStorageService extends Fake implements StorageService {
  bool isRecordingBlockedValue = false;
  
  @override
  bool get isRecordingBlocked => isRecordingBlockedValue;
}
```

### Widget Testing with Providers

```dart
await tester.pumpWidget(
  MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<CameraService>.value(value: mockCameraService),
        Provider<StorageService>.value(value: fakeStorageService),
      ],
      child: SlaveScreen(isAutoMode: true),
    ),
  ),
);
```

## Testing Camera and Media

Since real camera hardware isn't available in tests:

1. **Mock the camera controller** and platform channels
2. **Test camera service logic** independently
3. **Verify correct API calls** are made
4. **Test error handling** paths

For media upload:

1. **Mock the HTTP client** or API service
2. **Test queue management** logic
3. **Verify retry behavior** on failure
4. **Test network state handling**

## Continuous Integration

Add these commands to your CI pipeline:

```yaml
- flutter analyze  # Check for warnings/errors
- flutter test     # Run all tests
- flutter test --coverage  # Generate coverage report
```

## Writing New Tests

When adding a new feature:

1. **Identify the components** involved
2. **Write unit tests** for new services/logic
3. **Write widget tests** for new UI
4. **Write flow tests** for complete workflows
5. **Update this README** with new test files

## Coverage Goals

Target coverage by component:

- **Services**: >80% (core business logic)
- **Widgets**: >60% (UI components)
- **Flows**: Key user paths covered

## Known Limitations

- **Camera tests**: Cannot test actual camera hardware, only logic
- **Network tests**: Use mocked responses, not real API
- **Platform channels**: Mocked, not real native code
- **File I/O**: Tests use temporary directories

## Further Reading

- [Flutter Testing Guide](https://flutter.dev/docs/testing)
- [Mocktail Package](https://pub.dev/packages/mocktail)
- [Widget Testing](https://flutter.dev/docs/cookbook/testing/widget/introduction)
- [Integration Testing](https://flutter.dev/docs/testing/integration-tests)

