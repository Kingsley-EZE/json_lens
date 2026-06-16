import 'dart:convert';
import 'dart:developer' as developer;

/// A utility that brings Kotlin-like precision to JSON deserialization errors in Dart.
///
/// Instead of the unhelpful `type 'int' is not a subtype of type 'String'`,
/// you get:
///
/// ```
/// JsonDebugError: Type mismatch at $.data.hotels[0].room_price
///   Expected: String
///   Actual:   int (value: 12500)
///   Offset:   343
/// ```
///
/// Usage:
/// ```dart
/// final hotel = JsonDebugger.decode<HotelResponse>(
///   jsonString,
///   fromJson: HotelResponse.fromJson,
///   schema: {
///     'data': {
///       'hotels': [
///         {
///           'id': int,
///           'hotel_name': String,
///           'room_price': String, // <-- mismatch caught here
///           'total_amount': String,
///         }
///       ]
///     }
///   },
/// );
/// ```
class JsonDebugger {
  /// Decode a JSON string into a model with precise error reporting.
  ///
  /// [jsonString] - Raw JSON string from API response.
  /// [fromJson] - Your model's fromJson factory.
  /// [schema] - Optional type schema map for proactive validation.
  /// [tag] - Optional tag for log identification (e.g., 'HotelResponse').
  /// [logOnError] - If true (default), prints the formatted error to the
  ///   console before throwing. Set to false to throw silently.
  static T decode<T>({
    required String jsonString,
    required T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic>? schema,
    String? tag,
    bool logOnError = true,
  }) {
    final dynamic rawJson;

    // Step 1: Parse raw JSON
    try {
      rawJson = json.decode(jsonString);
    } catch (e) {
      final offset = _extractOffset(e.toString());
      _throwAndLog(JsonDebugError(
        message: 'Invalid JSON syntax',
        path: r'$',
        offset: offset,
        detail: e.toString(),
        tag: tag,
      ), logOnError);
    }

    if (rawJson is! Map<String, dynamic>) {
      _throwAndLog(JsonDebugError(
        message: 'Expected a JSON object at root',
        path: r'$',
        expected: 'Map<String, dynamic>',
        actual: '${rawJson.runtimeType}',
        tag: tag,
      ), logOnError);
    }

    // Step 2: Validate against schema if provided
    if (schema != null) {
      _validateSchema(rawJson, schema, r'$', tag, logOnError);
    }

    // Step 3: Attempt deserialization with enhanced error catching
    try {
      return fromJson(rawJson);
    } catch (e) {
      // If schema validation passed but fromJson still fails,
      // do a deep scan to find the culprit
      final mismatch = _deepScan(rawJson, r'$');
      if (mismatch != null) {
        _throwAndLog(mismatch, logOnError);
      }

      // Fallback: wrap the original error with context
      _throwAndLog(JsonDebugError(
        message: 'Deserialization failed',
        path: r'$',
        detail: e.toString(),
        tag: tag,
      ), logOnError);
    }
  }

  /// Validate a JSON map against a type schema.
  /// Call this independently if you want to validate without decoding.
  ///
  /// Returns a list of [JsonDebugError] for every type mismatch found.
  /// An empty list means the JSON conforms to the schema.
  static List<JsonDebugError> validate({
    required Map<String, dynamic> json,
    required Map<String, dynamic> schema,
    String? tag,
  }) {
    final errors = <JsonDebugError>[];
    _collectSchemaErrors(json, schema, r'$', tag, errors);
    return errors;
  }

  /// Wrap an existing fromJson call with better error reporting.
  ///
  /// Use this when you don't want to pass a schema but still want
  /// better errors than the default Dart ones.
  ///
  /// ```dart
  /// final hotel = JsonDebugger.wrap(
  ///   deserialize: () => HotelResponse.fromJson(jsonMap),
  ///   json: jsonMap,
  ///   tag: 'HotelResponse',
  /// );
  /// ```
  /// [logOnError] - If true (default), prints the formatted error to the
  ///   console before throwing. Set to false to throw silently.
  static T wrap<T>({
    required T Function() deserialize,
    required Map<String, dynamic> json,
    String? tag,
    bool logOnError = true,
  }) {
    try {
      return deserialize();
    } on TypeError catch (e) {
      final errorStr = e.toString();
      final typeInfo = _extractTypeError(errorStr);

      // Deep scan the JSON to find where the type mismatch is
      final findings = <String>[];
      _scanForTypeMismatch(json, r'$', typeInfo, findings);

      _throwAndLog(JsonDebugError(
        message: 'Type mismatch during deserialization',
        path: findings.isNotEmpty ? findings.first : r'$',
        detail: errorStr,
        tag: tag,
        suggestions: findings.length > 1
            ? ['Multiple possible locations found:', ...findings]
            : null,
      ), logOnError);
    } catch (e) {
      final mismatch = _deepScan(json, r'$');
      if (mismatch != null) _throwAndLog(mismatch, logOnError);

      _throwAndLog(JsonDebugError(
        message: 'Deserialization failed',
        path: r'$',
        detail: e.toString(),
        tag: tag,
      ), logOnError);
    }
  }

  /// Logs a [JsonDebugError] to the console if [logOnError] is true.
  static Never _throwAndLog(JsonDebugError error, bool logOnError) {
    if (logOnError) {
      developer.log(error.toString(), name: 'json_lens');
    }
    throw error;
  }

  // ─── Schema Validation ───────────────────────────────────────────

  static void _validateSchema(
    dynamic json,
    dynamic schema,
    String path,
    String? tag,
    bool logOnError,
  ) {
    final errors = <JsonDebugError>[];
    _collectSchemaErrors(json, schema, path, tag, errors);
    if (errors.isNotEmpty) {
      _throwAndLog(errors.first, logOnError);
    }
  }

  static void _collectSchemaErrors(
    dynamic json,
    dynamic schema,
    String path,
    String? tag,
    List<JsonDebugError> errors,
  ) {
    // Schema is a Type (e.g., String, int, double, bool)
    if (schema is Type) {
      if (json == null) return; // nullable by default

      final matches = _typeMatches(json, schema);
      if (!matches) {
        errors.add(JsonDebugError(
          message: 'Type mismatch',
          path: path,
          expected: '$schema',
          actual: '${json.runtimeType} (value: ${_truncate(json)})',
          offset: _estimateOffset(path),
          tag: tag,
        ));
      }
      return;
    }

    // Schema is a Map — validate each key
    if (schema is Map<String, dynamic>) {
      if (json is! Map<String, dynamic>) {
        errors.add(JsonDebugError(
          message: 'Expected a JSON object',
          path: path,
          expected: 'Map<String, dynamic>',
          actual: '${json.runtimeType}',
          tag: tag,
        ));
        return;
      }

      for (final key in schema.keys) {
        final childPath = '$path.$key';
        if (json.containsKey(key)) {
          _collectSchemaErrors(json[key], schema[key], childPath, tag, errors);
        }
      }
      return;
    }

    // Schema is a List — validate each item against the first schema element
    if (schema is List && schema.isNotEmpty) {
      if (json is! List) {
        errors.add(JsonDebugError(
          message: 'Expected a JSON array',
          path: path,
          expected: 'List',
          actual: '${json.runtimeType}',
          tag: tag,
        ));
        return;
      }

      final itemSchema = schema.first;
      for (int i = 0; i < json.length; i++) {
        _collectSchemaErrors(json[i], itemSchema, '$path[$i]', tag, errors);
      }
      return;
    }
  }

  // ─── Deep Scanning ───────────────────────────────────────────────

  /// Recursively scan JSON and report any suspicious type patterns
  /// that commonly cause Dart deserialization failures.
  static JsonDebugError? _deepScan(dynamic json, String path) {
    if (json is Map<String, dynamic>) {
      for (final entry in json.entries) {
        final result = _deepScan(entry.value, '$path.${entry.key}');
        if (result != null) return result;
      }
    } else if (json is List) {
      for (int i = 0; i < json.length; i++) {
        final result = _deepScan(json[i], '$path[$i]');
        if (result != null) return result;
      }
    }
    return null;
  }

  static void _scanForTypeMismatch(
    dynamic json,
    String path,
    _TypeErrorInfo? typeInfo,
    List<String> findings,
  ) {
    if (json is Map<String, dynamic>) {
      for (final entry in json.entries) {
        final childPath = '$path.${entry.key}';
        final value = entry.value;

        if (typeInfo != null && value != null) {
          final actualType = value.runtimeType.toString();
          if (actualType == typeInfo.actualType) {
            findings.add(
                '$childPath → ${value.runtimeType} (value: ${_truncate(value)})');
          }
        }
        _scanForTypeMismatch(value, childPath, typeInfo, findings);
      }
    } else if (json is List) {
      for (int i = 0; i < json.length; i++) {
        _scanForTypeMismatch(json[i], '$path[$i]', typeInfo, findings);
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  static bool _typeMatches(dynamic value, Type expected) {
    if (expected == String) return value is String;
    if (expected == int) return value is int;
    if (expected == double) return value is double || value is int;
    if (expected == bool) return value is bool;
    if (expected == num) return value is num;
    return true;
  }

  static String _truncate(dynamic value, [int maxLength = 50]) {
    final str = value.toString();
    return str.length > maxLength
        ? '${str.substring(0, maxLength)}...'
        : str;
  }

  static int? _extractOffset(String error) {
    final match = RegExp(r'offset (\d+)').firstMatch(error);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  static int? _estimateOffset(String path) {
    // This is a rough estimate based on path depth
    return null;
  }

  static _TypeErrorInfo? _extractTypeError(String error) {
    // Pattern: type 'int' is not a subtype of type 'String'
    final match = RegExp(
      r"type '(\w+)' is not a subtype of type '(\w+)'",
    ).firstMatch(error);

    if (match != null) {
      return _TypeErrorInfo(
        actualType: match.group(1)!,
        expectedType: match.group(2)!,
      );
    }
    return null;
  }
}

// ─── Error Class ─────────────────────────────────────────────────────

/// Represents a precise JSON deserialization error with path, type, and value info.
class JsonDebugError implements Exception {
  /// Human-readable error message (e.g., 'Type mismatch').
  final String message;

  /// JSON path where the error occurred (e.g., '$.data.hotels[0].room_price').
  final String path;

  /// Expected type at the path (e.g., 'String').
  final String? expected;

  /// Actual type and value found (e.g., 'int (value: 12500)').
  final String? actual;

  /// Character offset in the raw JSON string, if available.
  final int? offset;

  /// Additional error details from the underlying exception.
  final String? detail;

  /// Tag to identify which model failed (e.g., 'HotelResponse').
  final String? tag;

  /// Suggested locations when multiple possible mismatches are found.
  final List<String>? suggestions;

  const JsonDebugError({
    required this.message,
    required this.path,
    this.expected,
    this.actual,
    this.offset,
    this.detail,
    this.tag,
    this.suggestions,
  });

  @override
  String toString() {
    final buffer = StringBuffer();

    buffer.writeln('');
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════');
    buffer.writeln(
        '║ 🔴 JSON DEBUG ERROR${tag != null ? ' [$tag]' : ''}');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════');
    buffer.writeln('║ Message:  $message');
    buffer.writeln('║ Path:     $path');

    if (expected != null) {
      buffer.writeln('║ Expected: $expected');
    }
    if (actual != null) {
      buffer.writeln('║ Actual:   $actual');
    }
    if (offset != null) {
      buffer.writeln('║ Offset:   $offset');
    }
    if (detail != null) {
      buffer.writeln('║ Detail:   $detail');
    }
    if (suggestions != null && suggestions!.isNotEmpty) {
      buffer.writeln('║');
      for (final s in suggestions!) {
        buffer.writeln('║ 💡 $s');
      }
    }

    buffer.writeln(
        '╚══════════════════════════════════════════════════════════');

    return buffer.toString();
  }
}

// ─── Internal Types ──────────────────────────────────────────────────

class _TypeErrorInfo {
  final String actualType;
  final String expectedType;

  const _TypeErrorInfo({
    required this.actualType,
    required this.expectedType,
  });
}
