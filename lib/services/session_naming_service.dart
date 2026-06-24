class SessionNamingContext {
  const SessionNamingContext({
    required this.activityPreset,
    required this.sportsCenterName,
    required this.courtName,
    required this.players,
    required this.startTime,
  });

  final String activityPreset;
  final String? sportsCenterName;
  final String? courtName;
  final List<String> players;
  final DateTime startTime;
}

const sessionNamingService = SessionNamingService();

class SessionNamingService {
  const SessionNamingService();

  List<String> get activityPresets => const [
        "Squash match",
        "Padel match",
        "Training",
        "Drill",
        "Warm-up",
        "Custom",
      ];

  String get defaultActivityPreset => "Squash match";
  int get maxDisplayNameLength => 96;

  String defaultName(SessionNamingContext context) {
    final parts = <String>[];
    final activity = sanitizeCustomName(context.activityPreset);
    parts.add(activity.isEmpty || activity == "Custom" ? "Session" : activity);

    final location = _locationLabel(
      context.sportsCenterName,
      context.courtName,
    );
    if (location.isNotEmpty) {
      parts.add(location);
    }

    final playerLabel = _playerLabel(context.players);
    if (playerLabel.isNotEmpty) {
      parts.add(playerLabel);
    }

    parts.add(_formatLocalDateTime(context.startTime));
    return _truncate(parts.join(" - "));
  }

  String sanitizeCustomName(String rawName) {
    return rawName.trim().replaceAll(RegExp(r"\s+"), " ");
  }

  String _locationLabel(String? sportsCenterName, String? courtName) {
    final center = sanitizeCustomName(sportsCenterName ?? "");
    final court = sanitizeCustomName(courtName ?? "");
    if (center.isEmpty) {
      return court;
    }
    if (court.isEmpty) {
      return center;
    }
    return "$center $court";
  }

  String _playerLabel(List<String> players) {
    final cleanPlayers = players
        .map(sanitizeCustomName)
        .where((player) => player.isNotEmpty)
        .take(2)
        .toList();
    if (cleanPlayers.length == 2) {
      return "${cleanPlayers[0]} vs ${cleanPlayers[1]}";
    }
    if (cleanPlayers.length == 1) {
      return cleanPlayers.single;
    }
    return "";
  }

  String _formatLocalDateTime(DateTime value) {
    final localValue = value.toLocal();
    final year = localValue.year.toString().padLeft(4, "0");
    final month = localValue.month.toString().padLeft(2, "0");
    final day = localValue.day.toString().padLeft(2, "0");
    final hour = localValue.hour.toString().padLeft(2, "0");
    final minute = localValue.minute.toString().padLeft(2, "0");
    return "$year-$month-$day $hour:$minute";
  }

  String _truncate(String value) {
    if (value.length <= maxDisplayNameLength) {
      return value;
    }
    return value.substring(0, maxDisplayNameLength).trimRight();
  }
}
