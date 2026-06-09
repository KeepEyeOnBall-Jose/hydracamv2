import "dart:io";
import "dart:typed_data";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_media_storage.dart";

void main() {
  test("saveReceivedMedia writes photo bytes into the session directory",
      () async {
    final root = Directory.systemTemp.createTempSync("session_media_storage");
    final galleryCalls = <_GalleryCall>[];
    final storage = SessionMediaStorage(
      documentsDirectoryProvider: () async => root,
      galleryMediaPersistor: (filePath, mediaType) async {
        galleryCalls.add(_GalleryCall(filePath, mediaType));
      },
      now: () => DateTime.fromMillisecondsSinceEpoch(1770000000123),
    );

    try {
      final filePath = await storage.saveReceivedMedia(
        binaryData: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        sessionGuid: "session-guid",
        mediaType: SessionMediaType.photo,
      );

      expect(
        filePath,
        "${root.path}/session_session-guid/media_1770000000123.jpg",
      );
      expect(File(filePath).readAsBytesSync(), [0xFF, 0xD8, 0xFF]);
      expect(galleryCalls, hasLength(1));
      expect(galleryCalls.single.filePath, filePath);
      expect(galleryCalls.single.mediaType, SessionMediaType.photo);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test("saveReceivedMedia writes video bytes and dispatches video persistence",
      () async {
    final root = Directory.systemTemp.createTempSync("session_media_storage");
    final galleryCalls = <_GalleryCall>[];
    final storage = SessionMediaStorage(
      documentsDirectoryProvider: () async => root,
      galleryMediaPersistor: (filePath, mediaType) async {
        galleryCalls.add(_GalleryCall(filePath, mediaType));
      },
      now: () => DateTime.fromMillisecondsSinceEpoch(1770000000456),
    );

    try {
      final filePath = await storage.saveReceivedMedia(
        binaryData: Uint8List.fromList([0x00, 0x00, 0x00, 0x18]),
        sessionGuid: "session-guid",
        mediaType: SessionMediaType.video,
      );

      expect(
        filePath,
        "${root.path}/session_session-guid/media_1770000000456.mp4",
      );
      expect(File(filePath).readAsBytesSync(), [0x00, 0x00, 0x00, 0x18]);
      expect(galleryCalls, hasLength(1));
      expect(galleryCalls.single.filePath, filePath);
      expect(galleryCalls.single.mediaType, SessionMediaType.video);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test("saveReceivedMedia uses declared media type for file extension",
      () async {
    final root = Directory.systemTemp.createTempSync("session_media_storage");
    final storage = SessionMediaStorage(
      documentsDirectoryProvider: () async => root,
      galleryMediaPersistor: (filePath, mediaType) async {},
      now: () => DateTime.fromMillisecondsSinceEpoch(1770000000999),
    );

    try {
      final filePath = await storage.saveReceivedMedia(
        binaryData: Uint8List.fromList([0xFF, 0x00, 0x00, 0x18]),
        sessionGuid: "session-guid",
        mediaType: SessionMediaType.video,
      );

      expect(
        filePath,
        "${root.path}/session_session-guid/media_1770000000999.mp4",
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test("saveReceivedMedia requires an active session guid", () async {
    final root = Directory.systemTemp.createTempSync("session_media_storage");
    final storage = SessionMediaStorage(
      documentsDirectoryProvider: () async => root,
      galleryMediaPersistor: (filePath, mediaType) async {},
    );

    try {
      await expectLater(
        storage.saveReceivedMedia(
          binaryData: Uint8List.fromList([0xFF]),
          sessionGuid: "",
          mediaType: SessionMediaType.photo,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            "message",
            "Cannot save received media without an active session GUID.",
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

class _GalleryCall {
  const _GalleryCall(this.filePath, this.mediaType);

  final String filePath;
  final SessionMediaType mediaType;
}
