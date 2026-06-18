import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/models/session_upload_state.dart";

void main() {
  CapturedPhoto photo(String path, {required bool uploaded}) {
    return CapturedPhoto(
      photoPath: path,
      slaveDeviceId: "device-one",
      captureDate: DateTime(2026, 6, 18, 10),
      receivedDate: DateTime(2026, 6, 18, 10, 0, 1),
      isUploaded: uploaded,
    );
  }

  CapturedVideo video(String path, {required bool uploaded}) {
    return CapturedVideo(
      videoPath: path,
      slaveDeviceId: "device-one",
      startRecordingDate: DateTime(2026, 6, 18, 10, 1),
      endRecordingDate: DateTime(2026, 6, 18, 10, 1, 10),
      receivedDate: DateTime(2026, 6, 18, 10, 1, 11),
      isUploaded: uploaded,
    );
  }

  test("summarizes an empty session as not uploaded", () {
    final session = CaptureSession(
      sessionId: "empty-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.notUploaded);
    expect(summary.totalCount, 0);
    expect(summary.uploadedCount, 0);
    expect(summary.pendingCount, 0);
  });

  test("summarizes a session with no uploaded media as not uploaded", () {
    final session = CaptureSession(
      sessionId: "new-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
      capturedPhotos: [photo("one.jpg", uploaded: false)],
      capturedVideos: [video("one.mp4", uploaded: false)],
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.notUploaded);
    expect(summary.totalCount, 2);
    expect(summary.uploadedCount, 0);
    expect(summary.pendingCount, 2);
    expect(summary.label, "Not uploaded");
  });

  test("summarizes a mixed session as partially uploaded", () {
    final session = CaptureSession(
      sessionId: "mixed-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
      capturedPhotos: [photo("one.jpg", uploaded: true)],
      capturedVideos: [video("one.mp4", uploaded: false)],
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.partiallyUploaded);
    expect(summary.uploadedCount, 1);
    expect(summary.pendingCount, 1);
    expect(summary.label, "Partially uploaded");
  });

  test("summarizes a complete session as uploaded", () {
    final session = CaptureSession(
      sessionId: "complete-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
      capturedPhotos: [photo("one.jpg", uploaded: true)],
      capturedVideos: [video("one.mp4", uploaded: true)],
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.uploaded);
    expect(summary.uploadedCount, 2);
    expect(summary.pendingCount, 0);
    expect(summary.label, "Uploaded");
  });
}
