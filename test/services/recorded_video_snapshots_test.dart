import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/services/recorded_video_snapshots.dart";

void main() {
  late Directory directory;
  late RecordedVideoSnapshots store;
  final start = DateTime.utc(2026, 10, 24, 14, 46, 13);
  final stop = start.add(const Duration(seconds: 4));

  RecordedVideoSnapshot snapshot(String id, String path,
          {MediaCaptureContext? context}) =>
      RecordedVideoSnapshot.capture(
          captureId: id,
          path: path,
          startedAt: start,
          stoppedAt: stop,
          context: context);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp("recorded-context-test-");
    store =
        RecordedVideoSnapshots(directory: () async => directory, capacity: 2);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test("retained context is independent from later native-map changes",
      () async {
    // Protocol projection of the retained S10e exposure summary; no media
    // fixture or new sensor measurement is created by this unit test.
    final context = MediaCaptureContext.fromJson({
      "cameraName": "0",
      "exposure": {
        "preset": "shutter1_60",
        "lockStatus": "locked",
        "exposureTimeNs": 16666000,
        "iso": 3200,
        "lock": {"releaseStatus": "pending"}
      }
    })!;
    final captured = snapshot("capture-one", "original-path", context: context);
    await store.remember(captured);
    context.exposure!.lock!["releaseStatus"] = "released";
    final first = (await store.forPath("original-path"))!;
    first.context!.exposure!.lock!["releaseStatus"] = "mutated-by-reader";
    final second = (await store.forPath("original-path"))!;
    expect(second.context!.exposure!.lock!["releaseStatus"], "pending");
    expect(second.startedAt, start);
    expect(second.stoppedAt, stop);
  });

  test("concurrent readers and acknowledgement do not consume the first lookup",
      () async {
    final captured = snapshot("capture-one", "returned-path");
    await store.remember(captured);
    final readers = await Future.wait(
        [store.forPath("returned-path"), store.forPath("returned-path")]);
    expect(
        readers.map((value) => value?.captureId), everyElement("capture-one"));
    await store.acknowledge(captured);
    expect((await store.forPath("returned-path"))?.captureId, "capture-one");
  });

  test("pending receipt survives bounded memory eviction and a new store",
      () async {
    for (var index = 0; index < 3; index++) {
      await store.remember(snapshot("capture-$index", "path-$index"));
    }
    expect(store.cachedCount, lessThanOrEqualTo(2));
    final restarted =
        RecordedVideoSnapshots(directory: () async => directory, capacity: 2);
    final retained = await restarted.forPath("path-0");
    expect(retained?.captureId, "capture-0");
    expect(retained?.startedAt, start);
    expect(retained?.stoppedAt, stop);
  });

  test("acknowledgement removes only the matching metadata receipt", () async {
    final original = File("${directory.path}/source-sentinel");
    await original.writeAsString("non-media source; must remain untouched");
    final captured = snapshot("capture-one", original.path);
    await store.remember(captured);
    expect(await File("${directory.path}/capture-one.json").exists(), isTrue);
    await Future.wait(
        [store.acknowledge(captured), store.acknowledge(captured)]);
    expect(await original.exists(), isTrue);
    expect(await File("${directory.path}/capture-one.json").exists(), isFalse);
  });

  test("old acknowledgement cannot remove a new capture sharing a path",
      () async {
    final first = snapshot("capture-one", "reused-path");
    final second = snapshot("capture-two", "reused-path");
    await store.remember(first);
    await store.remember(second);
    await store.acknowledge(first);
    expect((await store.forPath("reused-path"))?.captureId, "capture-two");
    expect(await File("${directory.path}/capture-two.json").exists(), isTrue);
  });
}
