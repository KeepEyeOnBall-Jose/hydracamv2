/// Shared coercion helpers for parsing untyped JSON / `Map` values.
///
/// These were previously duplicated as byte-identical private helpers across
/// several model and service parsers (capture context, video metadata, camera
/// hardware metadata, master server, wearable replay, fixed-camera HLS).
/// Keeping a single copy avoids the helpers drifting apart over time.
library;

/// Coerces [value] to a [double] when possible, otherwise returns null.
///
/// Accepts a [double], any [num], or a numeric [String]; anything else yields
/// null.
double? toDoubleOrNull(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

/// Coerces [value] to an [int] when possible, otherwise returns null.
///
/// Accepts an [int], any [num] (truncated), or a numeric [String]; anything
/// else yields null.
int? toIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// Normalizes [value] into a `Map<String, dynamic>` when possible, otherwise
/// returns null.
///
/// A `Map<String, dynamic>` is returned as-is; any other [Map] is copied with
/// its keys stringified.
Map<String, dynamic>? toStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

/// Returns [value] when it is a non-empty [String], otherwise [fallback].
String stringOrFallback(Object? value, {required String fallback}) {
  return value is String && value.isNotEmpty ? value : fallback;
}

/// Returns [value] when it is a [bool], otherwise [fallback].
bool boolOrFallback(Object? value, {bool fallback = false}) {
  return value is bool ? value : fallback;
}

/// Coerces [value] to a trimmed, non-empty [String], throwing a
/// [FormatException] naming [fieldName] when it is missing or blank.
String requiredString(Object? value, String fieldName) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    throw FormatException("missing required field $fieldName");
  }
  return text;
}

/// Coerces [value] to an [int] when possible, otherwise returns null.
///
/// Accepts an [int], any [num] (rounded), or a numeric [String]; anything
/// else yields null.
int? roundedIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// Coerces [value] to a [DateTime] when possible, otherwise returns null.
///
/// A [DateTime] is returned as-is, an ISO-8601 [String] is parsed; anything
/// else yields null.
DateTime? optionalDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// Coerces [value] to a [DateTime], throwing a [FormatException] naming
/// [fieldName] when it is missing or unparseable.
DateTime requiredDateTime(Object? value, String fieldName) {
  final parsed = optionalDateTime(value);
  if (parsed == null) {
    throw FormatException("missing required field $fieldName");
  }
  return parsed;
}
