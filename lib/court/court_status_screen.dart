import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../services/log_service.dart";
import "court_channel.dart";

/// H19: read-only runtime status plus the manual enrollment form.
class CourtStatusScreen extends StatefulWidget {
  const CourtStatusScreen({
    super.key,
    required this.channel,
    this.pollInterval = const Duration(seconds: 1),
  });

  final CourtChannel channel;
  final Duration pollInterval;

  @override
  State<CourtStatusScreen> createState() => _CourtStatusScreenState();
}

class _CourtStatusScreenState extends State<CourtStatusScreen> {
  Map<String, Object?> _status = const {};
  String? _channelError;
  String? _enrollMessage;
  bool _busy = false;
  bool _showEnrollment = false;
  Timer? _timer;

  final _k2Url = TextEditingController();
  final _deviceId = TextEditingController();
  final _secret = TextEditingController();
  final _currentSecret = TextEditingController();
  final _courtId = TextEditingController();
  final _slot = TextEditingController();
  final _mountRev = TextEditingController(text: "0");

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [
      _k2Url,
      _deviceId,
      _secret,
      _currentSecret,
      _courtId,
      _slot,
      _mountRev,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await widget.channel.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _channelError = null;
        if (status["enrolled"] != true && !_showEnrollment) {
          _showEnrollment = true;
        }
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _channelError = error.message ?? error.code);
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _channelError = "court runtime not available");
    }
  }

  Future<void> _enroll() async {
    setState(() {
      _busy = true;
      _enrollMessage = null;
    });
    final input = CourtEnrollmentInput(
      k2Url: _k2Url.text.trim(),
      deviceId: _deviceId.text.trim(),
      secret: _secret.text,
      courtId: _courtId.text.trim(),
      slot: _slot.text.trim(),
      mountRev: int.tryParse(_mountRev.text.trim()) ?? 0,
      currentSecret: _enrolled ? _currentSecret.text : null,
    );
    String? error;
    try {
      error = await widget.channel.enroll(input);
    } on PlatformException catch (failure) {
      error = failure.message ?? failure.code;
    }
    if (!mounted) return;
    if (error == null) {
      _secret.clear();
      _currentSecret.clear();
      LogService.instance.registerLog(
        "Court enrollment saved.",
        file: "court_status_screen.dart",
      );
    }
    setState(() {
      _busy = false;
      _enrollMessage = error ?? "Enrolled.";
      _showEnrollment = error != null;
    });
    await _refresh();
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _enrollMessage = null;
    });
    String? error;
    try {
      error = await widget.channel.clearEnrollment(
        currentSecret: _currentSecret.text,
      );
    } on PlatformException catch (failure) {
      error = failure.message ?? failure.code;
    }
    if (!mounted) return;
    if (error == null) _currentSecret.clear();
    setState(() {
      _busy = false;
      _enrollMessage = error ?? "Enrollment cleared.";
      _showEnrollment = true;
    });
    await _refresh();
  }

  bool get _enrolled => _status["enrolled"] == true;

  String _text(String key) {
    final value = _status[key];
    if (value == null) return "-";
    return value.toString();
  }

  String _bytes(String key) {
    final value = _status[key];
    if (value is! num) return "-";
    const gib = 1024 * 1024 * 1024;
    const mib = 1024 * 1024;
    if (value >= gib) return "${(value / gib).toStringAsFixed(1)} GiB";
    return "${(value / mib).toStringAsFixed(1)} MiB";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooted = _status["rooted"] == true;
    final connected = _status["connected"] == true;
    final logs = (_status["logs"] as List?)?.cast<Object?>() ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text("HydraCam Court"),
        actions: [
          IconButton(
            tooltip: "Start service",
            icon: const Icon(Icons.play_circle_outline),
            onPressed: _busy ? null : () => widget.channel.startService(),
          ),
          IconButton(
            tooltip: "Enrollment",
            icon: const Icon(Icons.key),
            onPressed: () => setState(() => _showEnrollment = !_showEnrollment),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_channelError != null)
            Text(_channelError!,
                style: TextStyle(color: theme.colorScheme.error)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(label: rooted ? "rooted" : "NOT ROOTED", ok: rooted),
              _Badge(
                  label: connected ? "K2 connected" : "K2 offline",
                  ok: connected),
              _Badge(
                  label: "mode ${_text("mode")}",
                  ok: _status["lastError"] == null),
              _Badge(label: "phase ${_text("phase")}", ok: true),
            ],
          ),
          const SizedBox(height: 12),
          _Section(title: "Device", rows: {
            "Device": _text("deviceId"),
            "Court / slot": "${_text("courtId")} / ${_text("slot")}",
            "Mount rev": _text("mountRev"),
            "K2": _text("k2Url"),
            "Connect error": _text("connectError"),
          }),
          _Section(title: "Recording", rows: {
            "Session": _text("activeSessionId"),
            "Camera": _text("camera"),
            "Last error": _text("lastError"),
            "Clock offset":
                "${_text("clockOffsetMs")} ms (rtt ${_text("clockRttMs")} ms)",
            "Pending uploads":
                "${_text("pendingUploads")} (${_bytes("pendingUploadBytes")})",
          }),
          _Section(title: "Health", rows: {
            "Battery": "${_text("batteryPct")}% charging=${_text("charging")}",
            "Temp": "${_text("tempC")} C thermal=${_text("thermal")}",
            "Free": _bytes("freeBytes"),
          }),
          if (_showEnrollment) _enrollmentForm(theme),
          const SizedBox(height: 12),
          Text("Log", style: theme.textTheme.titleSmall),
          for (final line in logs.reversed.take(40))
            Text(
              line.toString(),
              style:
                  theme.textTheme.bodySmall?.copyWith(fontFamily: "monospace"),
            ),
        ],
      ),
    );
  }

  Widget _enrollmentForm(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Enrollment", style: theme.textTheme.titleMedium),
            if (_enrolled)
              _field(
                _currentSecret,
                "Current device secret (to change or clear)",
                obscure: true,
              ),
            _field(_k2Url, "K2 URL (https://…)"),
            _field(_deviceId, "Device id"),
            _field(_secret, "Device secret", obscure: true),
            _field(_courtId, "Court id"),
            _field(_slot, "Slot"),
            _field(_mountRev, "Mount rev", number: true),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : _enroll,
                  child: const Text("Enroll"),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy || !_enrolled ? null : _clear,
                  child: const Text("Clear"),
                ),
              ],
            ),
            if (_enrollMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_enrollMessage!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: ok ? scheme.secondaryContainer : scheme.errorContainer,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(entry.key, style: theme.textTheme.bodySmall),
                    ),
                    Expanded(child: Text(entry.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
