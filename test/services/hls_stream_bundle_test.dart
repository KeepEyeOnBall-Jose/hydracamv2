import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/hls_stream_bundle.dart";

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync("hydracam_hls_bundle_test");
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
      "fromDirectory parses playlist init segment and chunks in playlist order",
      () async {
    File("${tempDir.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
squash-court-a-00000000.m4s
#EXTINF:2.0,
squash-court-a-00000001.m4s
#EXT-X-ENDLIST
""");
    File("${tempDir.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
    File("${tempDir.path}/squash-court-a-00000001.m4s")
        .writeAsBytesSync([1, 1, 1]);
    File("${tempDir.path}/squash-court-a-00000000.m4s")
        .writeAsBytesSync([0, 0]);

    final bundle = await HlsStreamBundle.fromDirectory(tempDir);

    expect(bundle.playlist.path, endsWith("playlist.m3u8"));
    expect(bundle.initSegment?.path, endsWith("init.mp4"));
    expect(
      bundle.chunks.map((chunk) => chunk.path.split("/").last).toList(),
      ["squash-court-a-00000000.m4s", "squash-court-a-00000001.m4s"],
    );
    expect(bundle.targetDuration, const Duration(seconds: 2));
    expect(bundle.totalBytes, 9);
  });

  test("fromDirectory rejects playlists that reference missing chunks",
      () async {
    File("${tempDir.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXTINF:2.0,
missing-segment.m4s
""");

    expect(
      () => HlsStreamBundle.fromDirectory(tempDir),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          "message",
          contains("missing-segment.m4s"),
        ),
      ),
    );
  });
}
