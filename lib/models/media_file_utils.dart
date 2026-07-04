import "dart:io";

/// Returns the size, in bytes, of the file at [path], or 0 when the file does
/// not exist or cannot be read. Never throws.
///
/// Shared by the captured-media models ([CapturedPhoto], [CapturedVideo]) so the
/// "best effort" file-size logic lives in one place.
int safeFileSizeOf(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) {
      return file.lengthSync();
    }
  } catch (_) {}
  return 0;
}
