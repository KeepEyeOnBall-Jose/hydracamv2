import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/automation/automation_bridge.dart";
import "package:hydracam/services/log_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("health snapshot exposes automation target identity", () {
    final health = AutomationBridge.instance.buildHealthSnapshot();

    expect(health["status"], "ok");
    expect(health["automation"], isTrue);
    expect(health, contains("automationTargetId"));
  });

  test("stale automation handler unregister does not remove current handler",
      () {
    final bridge = AutomationBridge.instance;
    final command = "race_test_${DateTime.now().microsecondsSinceEpoch}";

    Future<Map<String, dynamic>> staleHandler(
        Map<String, dynamic> payload) async {
      return {"handler": "stale"};
    }

    Future<Map<String, dynamic>> currentHandler(
        Map<String, dynamic> payload) async {
      return {"handler": "current"};
    }

    addTearDown(() {
      bridge.unregisterCommands([command]);
    });

    bridge.registerCommand(command, staleHandler);
    bridge.registerCommand(command, currentHandler);

    bridge.unregisterCommandsIfCurrent({command: staleHandler});

    expect(bridge.isCommandRegistered(command), isTrue);

    bridge.unregisterCommandsIfCurrent({command: currentHandler});

    expect(bridge.isCommandRegistered(command), isFalse);
  });

  test("automation port collision does not throw during startup", () async {
    final reservedServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final bridge = AutomationBridge.forTesting(
      automationEnabled: true,
      automationServerPort: reservedServer.port,
    );

    addTearDown(() async {
      await bridge.closeForTesting();
      await reservedServer.close(force: true);
      LogService.instance.clearLogs();
    });

    await expectLater(bridge.ensureInitialized(), completes);

    expect(bridge.isRunning, isFalse);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(contains("Automation bridge unavailable")),
    );
  });

  test("malformed command JSON returns bad request without invoking handler",
      () async {
    final reservedServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = reservedServer.port;
    await reservedServer.close(force: true);

    final bridge = AutomationBridge.forTesting(
      automationEnabled: true,
      automationServerPort: port,
    );
    var handlerInvoked = false;
    const command = "malformed_body_test";
    bridge.registerCommand(command, (payload) async {
      handlerInvoked = true;
      return {"ok": true};
    });
    addTearDown(() async {
      bridge.unregisterCommands([command]);
      await bridge.closeForTesting();
      LogService.instance.clearLogs();
    });

    await bridge.ensureInitialized();

    const body = "{malformed-json";
    final bodyBytes = utf8.encode(body);
    final requestBytes = utf8.encode(
      "POST /commands/$command HTTP/1.1\r\n"
      "Host: 127.0.0.1:$port\r\n"
      "Content-Type: application/json\r\n"
      "Content-Length: ${bodyBytes.length}\r\n"
      "Connection: close\r\n"
      "\r\n",
    );
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.add(requestBytes);
    socket.add(bodyBytes);
    await socket.flush();
    final rawResponse = await utf8.decoder.bind(socket).join();
    final responseParts = rawResponse.split("\r\n\r\n");
    final payload = jsonDecode(_decodeHttpResponseBody(rawResponse))
        as Map<String, dynamic>;

    expect(
        responseParts.first, startsWith("HTTP/1.1 ${HttpStatus.badRequest}"));
    expect(payload["error"], "invalid_request");
    expect(handlerInvoked, isFalse);
  });
}

String _decodeHttpResponseBody(String rawResponse) {
  final responseParts = rawResponse.split("\r\n\r\n");
  final headers = responseParts.first.toLowerCase();
  final body = responseParts.sublist(1).join("\r\n\r\n");
  if (!headers.contains("transfer-encoding: chunked")) {
    return body;
  }

  var remainingBody = body;
  final decodedBody = StringBuffer();
  while (remainingBody.isNotEmpty) {
    final sizeLineEnd = remainingBody.indexOf("\r\n");
    if (sizeLineEnd < 0) {
      break;
    }
    final chunkSize = int.parse(
      remainingBody.substring(0, sizeLineEnd).trim(),
      radix: 16,
    );
    if (chunkSize == 0) {
      break;
    }
    final chunkStart = sizeLineEnd + 2;
    decodedBody.write(
      remainingBody.substring(chunkStart, chunkStart + chunkSize),
    );
    remainingBody = remainingBody.substring(chunkStart + chunkSize + 2);
  }
  return decodedBody.toString();
}
