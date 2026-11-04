import "dart:async";
import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";

/// Mock K2 (C0 token + C1 device WS) and K3 (C2 ingest) for court runtime
/// hardware checks. Pure `dart:io`; run on the host and expose it to the
/// phone with `adb reverse tcp:<port> tcp:<port>`:
///
///     dart run tool/court_mock_k2.dart --out logs/verification-runs/<run>
///
/// Scenario: wait `--idle-s` after the first hello (the phone must not record),
/// send record.prepare, record.start (+ rec.start signal), record for
/// `--record-s`, send record.stop (+ rec.stop signal), then wait for every
/// segment to verify and the manifest to complete, and write `summary.json`.
/// `--no-signals` skips both signal.emit messages, so the phone plays no tones.
Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final mock = _MockK2(options);
  await mock.run();
}

class _Options {
  _Options({
    required this.port,
    required this.out,
    required this.idleS,
    required this.recordS,
    required this.audio,
    required this.tiers,
    required this.exitAfterS,
    required this.signals,
  });

  final int port;
  final Directory out;
  final int idleS;
  final int recordS;
  final bool audio;
  final List<String> tiers;
  final int exitAfterS;
  final bool signals;

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith("--")) continue;
      final name = arg.substring(2);
      if (name == "audio" || name == "no-signals") {
        values[name] = "true";
      } else if (i + 1 < args.length) {
        values[name] = args[++i];
      }
    }
    final out = values["out"];
    if (out == null) {
      stderr.writeln("usage: court_mock_k2.dart --out <dir> [--port 8787] "
          "[--idle-s 20] [--record-s 30] [--audio] [--tiers proxy,master] "
          "[--exit-after-s 900] [--no-signals]");
      exit(64);
    }
    return _Options(
      port: int.parse(values["port"] ?? "8787"),
      out: Directory(out),
      idleS: int.parse(values["idle-s"] ?? "20"),
      recordS: int.parse(values["record-s"] ?? "30"),
      audio: values["audio"] == "true",
      tiers: (values["tiers"] ?? "proxy,master").split(","),
      exitAfterS: int.parse(values["exit-after-s"] ?? "900"),
      signals: values["no-signals"] != "true",
    );
  }
}

class _Upload {
  _Upload(
      this.key, this.sessionId, this.tier, this.seq, this.bytes, this.sha256);

  final String key;
  final String sessionId;
  final String tier;
  final int seq;
  final int bytes;
  final String sha256;
  final Map<int, List<int>> parts = {};
  String state = "uploading";
  String? reason;
}

class _MockK2 {
  _MockK2(this.options);

  static const _partSize = 16 * 1024 * 1024;

  final _Options options;
  final _uploads = <String, _Upload>{};
  final _verified = <String, _Upload>{};
  final _segmentEvents = <String, int>{};
  final _done = Completer<void>();
  late final IOSink _c1Log;
  late final IOSink _c2Log;
  WebSocket? _socket;
  int _nextId = 0;
  int? _firstHelloMs;
  int? _recordStartSentMs;
  int? _recordStopSentMs;
  int? _firstSegmentEventMs;
  int _segmentEventsBeforeStart = 0;
  bool? _rooted;
  String? _startRef;
  String? _startAck;
  int? _startAtServerMs;
  String? _sessionId;
  bool _leaseActive = false;
  bool _manifestComplete = false;
  bool _scenarioStarted = false;
  // A socket's onDone can fire after shutdown closed the logs.
  bool _logsClosed = false;
  final _startedEvents = <Map<String, Object?>>[];
  final _stoppedEvents = <Map<String, Object?>>[];

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> run() async {
    options.out.createSync(recursive: true);
    _c1Log = File("${options.out.path}/c1.jsonl").openWrite();
    _c2Log = File("${options.out.path}/c2.jsonl").openWrite();
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, options.port);
    stdout.writeln(
        "mock K2 on http://127.0.0.1:${options.port} → ${options.out.path}");
    server.listen(_handle);
    final timeout = Timer(Duration(seconds: options.exitAfterS), () {
      if (!_done.isCompleted) _done.complete();
    });
    await _done.future;
    timeout.cancel();
    await _writeSummary();
    await _socket?.close();
    await server.close(force: true);
    _logsClosed = true;
    await _c1Log.close();
    await _c2Log.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    try {
      if (path == "/device/v1" &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        await _acceptSocket(request);
      } else if (path == "/device/v1/token" && request.method == "POST") {
        await _token(request);
      } else if (path == "/v2/uploads" && request.method == "POST") {
        await _initUpload(request);
      } else if (path.startsWith("/v2/parts/") && request.method == "PUT") {
        await _putPart(request);
      } else if (path.startsWith("/v2/uploads/") &&
          path.endsWith("/complete")) {
        await _complete(request);
      } else if (path.startsWith("/v2/uploads/") && request.method == "GET") {
        await _status(request);
      } else if (path.startsWith("/v2/sessions/") &&
          path.endsWith("/manifest")) {
        await _manifest(request);
      } else {
        await _json(request, 404, {"error": "not_found"});
      }
    } on Object catch (error) {
      stderr.writeln("request $path failed: $error");
      await _json(request, 500, {"error": "$error"});
    }
  }

  Future<void> _token(HttpRequest request) async {
    final body = await _readJson(request);
    final secret = body["secret"];
    final ok =
        body["deviceId"] is String && secret is String && secret.isNotEmpty;
    _logC2("token", {"deviceId": body["deviceId"], "ok": ok});
    if (!ok) {
      await _json(request, 401, {"error": "bad_credentials"});
      return;
    }
    await _json(request, 200, {
      "accessToken": "mock-access-$_now",
      "expiresAt": _now ~/ 1000 + 3600,
    });
  }

  Future<void> _acceptSocket(HttpRequest request) async {
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? "";
    if (!auth.startsWith("Bearer mock-access-")) {
      _logC1("in", "reject", {"reason": "bad_bearer"});
      request.response.statusCode = 401;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request,
        compression: CompressionOptions.compressionOff);
    await _socket?.close();
    _socket = socket;
    socket.listen(
      (data) => _onFrame(data as String),
      onDone: () => _logC1("in", "closed", {}),
    );
  }

  void _onFrame(String text) {
    final received = _now;
    final envelope = jsonDecode(text) as Map<String, Object?>;
    final type = envelope["type"] as String;
    final body = (envelope["body"] as Map?)?.cast<String, Object?>() ?? {};
    _logC1("in", type, envelope);
    switch (type) {
      case "clock.ping":
        _send("clock.pong", {"t0": body["t0"], "t1": received, "t2": _now});
      case "state":
        break;
      case "ack":
      case "nack":
        if (body["ref"] == _startRef) {
          _startAck = type == "ack" ? "ack" : "nack:${body["code"]}";
        }
      case "hello":
        _ack(envelope);
        _onHello(body);
      default:
        _ack(envelope);
        _onDeviceEvent(type, body, received);
    }
  }

  void _onHello(Map<String, Object?> body) {
    _rooted = body["rooted"] == true;
    if (_firstHelloMs == null) {
      _firstHelloMs = _now;
      _scheduleScenario();
      return;
    }
    // C1: re-send the lease on each reconnect.
    if (_leaseActive) {
      _sendRecordStart(resend: true);
    } else if (_sessionId != null && _recordStopSentMs != null) {
      _send("record.stop", {"sessionId": _sessionId, "stopAtServerMs": _now});
    }
  }

  void _onDeviceEvent(String type, Map<String, Object?> body, int received) {
    switch (type) {
      case "recording.started":
        _startedEvents.add(body);
      case "recording.segment":
        final tier = body["tier"] as String;
        _segmentEvents[tier] = (_segmentEvents[tier] ?? 0) + 1;
        _firstSegmentEventMs ??= received;
        if (_recordStartSentMs == null || received < _recordStartSentMs!) {
          _segmentEventsBeforeStart += 1;
        }
      case "recording.stopped":
        _stoppedEvents.add(body);
    }
  }

  void _scheduleScenario() {
    if (_scenarioStarted) return;
    _scenarioStarted = true;
    _sessionId = "mock-$_now";
    Timer(Duration(seconds: options.idleS), () {
      _send("record.prepare", {
        "sessionId": _sessionId,
        "profile": {"masterRes": "1920x1080", "fps": 30, "segmentS": 6},
      });
      Timer(const Duration(seconds: 2), () {
        _leaseActive = true;
        _sendRecordStart(resend: false);
        Timer(Duration(seconds: options.recordS), _stopScenario);
      });
    });
  }

  void _sendRecordStart({required bool resend}) {
    _startAtServerMs ??= _now + 2000;
    _recordStartSentMs ??= _now;
    final exp = _now ~/ 1000 + 24 * 3600;
    final grant = _unsignedJwt({
      "aud": "court-ingest",
      "sid": _sessionId,
      "slot": "mock-slot",
      "tiers": options.tiers,
      "exp": exp,
    });
    _startRef = _send("record.start", {
      "sessionId": _sessionId,
      "leaseId": "lease-$_sessionId",
      "requestedBy": "mock",
      "startAtServerMs": _startAtServerMs,
      "maxDurationS": options.recordS + 120,
      "audio": options.audio,
      "uploadGrant": grant,
      "ingestUrl": "http://127.0.0.1:${options.port}",
      "gestures": <String>[],
    });
    if (!resend && options.signals) {
      _send("signal.emit", {
        "signal": "rec.start",
        "atServerMs": _startAtServerMs,
        "sessionId": _sessionId,
      });
    }
  }

  void _stopScenario() {
    final stopAt = _now + 1000;
    _leaseActive = false;
    _recordStopSentMs = _now;
    if (options.signals) {
      _send("signal.emit", {
        "signal": "rec.stop",
        "atServerMs": stopAt,
        "sessionId": _sessionId,
      });
    }
    _send("record.stop", {"sessionId": _sessionId, "stopAtServerMs": stopAt});
  }

  void _ack(Map<String, Object?> envelope) {
    _send("ack", {"ref": envelope["id"]});
  }

  String _send(String type, Map<String, Object?> body) {
    final id = "k2-${_nextId++}";
    final envelope = {"v": 1, "id": id, "type": type, "ts": _now, "body": body};
    _logC1("out", type, envelope);
    _socket?.add(jsonEncode(envelope));
    return id;
  }

  Future<void> _initUpload(HttpRequest request) async {
    if (!_grantOk(request)) {
      await _json(request, 401, {"error": "bad_grant"});
      return;
    }
    final body = await _readJson(request);
    final key = "${body["sessionId"]}/${body["tier"]}/${body["seq"]}";
    final sha = body["sha256"] as String;
    final done = _verified[key];
    if (done != null) {
      _logC2("init", {"key": key, "result": done.sha256 == sha ? 200 : 409});
      if (done.sha256 == sha) {
        await _json(request, 200, {"uploadId": key, "state": "verified"});
      } else {
        await _json(request, 409, {"reason": "different bytes"});
      }
      return;
    }
    final bytes = (body["bytes"] as num).toInt();
    final upload = _Upload(key, body["sessionId"] as String,
        body["tier"] as String, (body["seq"] as num).toInt(), bytes, sha);
    final uploadId = "u${_uploads.length}";
    _uploads[uploadId] = upload;
    final origin = request.requestedUri.origin;
    final partCount = bytes == 0 ? 1 : (bytes + _partSize - 1) ~/ _partSize;
    _logC2("init",
        {"key": key, "uploadId": uploadId, "bytes": bytes, "parts": partCount});
    await _json(request, 201, {
      "uploadId": uploadId,
      "partSize": _partSize,
      "parts": [
        for (var n = 1; n <= partCount; n++)
          {"n": n, "url": "$origin/v2/parts/$uploadId/$n"},
      ],
    });
  }

  Future<void> _putPart(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final upload = _uploads[segments[2]];
    final n = int.parse(segments[3]);
    final data = await request
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    if (upload == null) {
      await _json(request, 404, {"error": "unknown_upload"});
      return;
    }
    upload.parts[n] = data;
    final etag = sha256.convert(data).toString().substring(0, 16);
    _logC2("part", {"key": upload.key, "n": n, "bytes": data.length});
    request.response.headers.set("ETag", etag);
    request.response.statusCode = 200;
    await request.response.close();
  }

  Future<void> _complete(HttpRequest request) async {
    final upload = _uploads[request.uri.pathSegments[2]];
    if (upload == null) {
      await _json(request, 404, {"error": "unknown_upload"});
      return;
    }
    final numbers = upload.parts.keys.toList()..sort();
    final bytes = <int>[for (final n in numbers) ...upload.parts[n]!];
    final digest = sha256.convert(bytes).toString();
    if (digest == upload.sha256 && bytes.length == upload.bytes) {
      upload.state = "verified";
      _verified[upload.key] = upload;
      final file = File(
          "${options.out.path}/store/${upload.sessionId}/${upload.tier}/${upload.seq}.ts");
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    } else {
      upload.state = "failed";
      upload.reason = "sha256 mismatch";
    }
    upload.parts.clear();
    _logC2("complete",
        {"key": upload.key, "state": upload.state, "bytes": bytes.length});
    await _json(request, 202, {"state": "verifying"});
  }

  Future<void> _status(HttpRequest request) async {
    final upload = _uploads[request.uri.pathSegments[2]];
    if (upload == null) {
      await _json(request, 404, {"error": "unknown_upload"});
      return;
    }
    await _json(request, 200, {"state": upload.state, "reason": upload.reason});
  }

  Future<void> _manifest(HttpRequest request) async {
    final body = await _readJson(request);
    final listed = (body["segments"] as List).cast<Map<String, Object?>>();
    final sid = request.uri.pathSegments[2];
    final missing = [
      for (final entry in listed)
        if (!_verified.containsKey("$sid/${entry["tier"]}/${entry["seq"]}"))
          {"tier": entry["tier"], "seq": entry["seq"]},
    ];
    final state = missing.isEmpty ? "complete" : "partial";
    _logC2("manifest", {
      "sessionId": sid,
      "listed": listed.length,
      "missing": missing.length,
      "lastSeq": body["lastSeq"]
    });
    await _json(request, 200, {"state": state, "missing": missing});
    if (state == "complete") {
      _manifestComplete = true;
      Timer(const Duration(seconds: 5), () {
        if (!_done.isCompleted) _done.complete();
      });
    }
  }

  bool _grantOk(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? "";
    return auth.startsWith("Bearer ") && auth.split(".").length == 3;
  }

  Future<void> _writeSummary() async {
    final verifiedByTier = <String, int>{};
    for (final upload in _verified.values) {
      verifiedByTier[upload.tier] = (verifiedByTier[upload.tier] ?? 0) + 1;
    }
    final summary = {
      "sessionId": _sessionId,
      "rooted": _rooted,
      "firstHelloMs": _firstHelloMs,
      "recordStartSentMs": _recordStartSentMs,
      "recordStartReply": _startAck,
      "recordStopSentMs": _recordStopSentMs,
      "firstSegmentEventMs": _firstSegmentEventMs,
      "segmentEventsBeforeRecordStart": _segmentEventsBeforeStart,
      "segmentEventsByTier": _segmentEvents,
      "verifiedUploadsByTier": verifiedByTier,
      "failedUploads": _uploads.values.where((u) => u.state == "failed").length,
      "manifestComplete": _manifestComplete,
      "recordingStarted": _startedEvents,
      "recordingStopped": _stoppedEvents,
    };
    final text = const JsonEncoder.withIndent("  ").convert(summary);
    await File("${options.out.path}/summary.json").writeAsString("$text\n");
    stdout.writeln(text);
  }

  void _logC1(String direction, String type, Map<String, Object?> envelope) {
    if (_logsClosed) return;
    _c1Log.writeln(jsonEncode({
      "serverMs": _now,
      "dir": direction,
      "type": type,
      "envelope": envelope
    }));
  }

  void _logC2(String event, Map<String, Object?> fields) {
    if (_logsClosed) return;
    _c2Log.writeln(jsonEncode({"serverMs": _now, "event": event, ...fields}));
  }

  Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.isEmpty) return {};
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  Future<void> _json(HttpRequest request, int status, Object body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  String _unsignedJwt(Map<String, Object?> claims) {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll("=", "");
    return "${encode({"alg": "none", "typ": "JWT"})}.${encode(claims)}.mock";
  }
}
