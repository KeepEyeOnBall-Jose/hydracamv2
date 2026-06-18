import "capture_session.dart";

enum SessionUploadState {
  notUploaded,
  partiallyUploaded,
  uploaded,
}

class SessionUploadSummary {
  const SessionUploadSummary({
    required this.state,
    required this.totalCount,
    required this.uploadedCount,
    required this.pendingCount,
  });

  final SessionUploadState state;
  final int totalCount;
  final int uploadedCount;
  final int pendingCount;

  String get label {
    return switch (state) {
      SessionUploadState.notUploaded => "Not uploaded",
      SessionUploadState.partiallyUploaded => "Partially uploaded",
      SessionUploadState.uploaded => "Uploaded",
    };
  }
}

SessionUploadSummary summarizeSessionUpload(CaptureSession session) {
  final totalCount =
      session.capturedPhotos.length + session.capturedVideos.length;
  final uploadedCount =
      session.capturedPhotos.where((item) => item.isUploaded).length +
          session.capturedVideos.where((item) => item.isUploaded).length;
  final pendingCount = totalCount - uploadedCount;

  final SessionUploadState state;
  if (totalCount == 0 || uploadedCount == 0) {
    state = SessionUploadState.notUploaded;
  } else if (uploadedCount == totalCount) {
    state = SessionUploadState.uploaded;
  } else {
    state = SessionUploadState.partiallyUploaded;
  }

  return SessionUploadSummary(
    state: state,
    totalCount: totalCount,
    uploadedCount: uploadedCount,
    pendingCount: pendingCount,
  );
}
