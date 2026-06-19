import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/hls_playlist_manifest.dart";

void main() {
  test("render matches the native fixed-camera HLS playlist shape", () {
    final playlist = HlsPlaylistManifest(
      initFileName: "init.mp4",
      segments: const [
        HlsPlaylistSegment(
          fileName: "device-stream-00000000.m4s",
          duration: Duration(milliseconds: 1850),
        ),
        HlsPlaylistSegment(
          fileName: "device-stream-00000001.m4s",
          duration: Duration(milliseconds: 2000),
        ),
      ],
      isFinal: true,
    );

    expect(
      playlist.render(),
      """
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="init.mp4"
#EXTINF:1.850,
device-stream-00000000.m4s
#EXTINF:2.000,
device-stream-00000001.m4s
#EXT-X-ENDLIST
""".trimLeft(),
    );
  });

  test("chunkFileName pads chunk numbers to eight digits", () {
    expect(
      HlsPlaylistManifest.chunkFileName(
        deviceId: "device",
        streamId: "stream",
        chunkNumber: 0,
      ),
      "device-stream-00000000.m4s",
    );
    expect(
      HlsPlaylistManifest.chunkFileName(
        deviceId: "device",
        streamId: "stream",
        chunkNumber: 12,
      ),
      "device-stream-00000012.m4s",
    );
    expect(
      HlsPlaylistManifest.chunkFileName(
        deviceId: "device",
        streamId: "stream",
        chunkNumber: 12345678,
      ),
      "device-stream-12345678.m4s",
    );
  });
}
