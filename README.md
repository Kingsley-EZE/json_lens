# json_lens

**Kotlin-like precision for JSON deserialization errors in Dart.**

Stop wasting 30 minutes debugging `type 'int' is not a subtype of type 'String'`.

## The Problem

In Kotlin (`kotlinx.serialization`), when JSON deserialization fails you get:

```
Expected quotation mark '"', but had '1' instead at path: $.data.hotels[0].room_price
```

In Dart/Flutter, you get:

```
type 'int' is not a subtype of type 'String'
```

No field name. No JSON path. No indication of where in a 500-line API response the mismatch happened. You're left adding print statements until you find it.

## The Solution

`json_lens` catches JSON deserialization errors and reports exactly what went wrong:

```
╔══════════════════════════════════════════════════════════
║ 🔴 JSON DEBUG ERROR [HotelResponse]
╠══════════════════════════════════════════════════════════
║ Message:  Type mismatch
║ Path:     $.data.hotels[0].room_price
║ Expected: String
║ Actual:   int (value: 12500)
╚══════════════════════════════════════════════════════════
```

## Installation

```yaml
dependencies:
  json_lens: ^0.0.2
```

```dart
import 'package:json_lens/json_lens.dart';
```

## Usage

### Method 1: `wrap()` — Wrap existing fromJson (easiest migration)

One-line change. No schema needed. When a `TypeError` occurs, `json_lens` scans the JSON tree to locate the likely culprit. This is the recommended starting point for most projects.

```dart
// Before:
final response = HotelResponse.fromJson(jsonMap);

// After:
final response = JsonDebugger.wrap<HotelResponse>(
  deserialize: () => HotelResponse.fromJson(jsonMap),
  json: jsonMap,
  tag: 'HotelResponse',
);
```

### Method 2: `decode()` — Full decode with schema (best precision)

Define a type schema matching your expected JSON structure. `json_lens` validates every field *before* `fromJson` runs, so the error points to the exact path. Best for critical endpoints or contract testing.

```dart
final response = JsonDebugger.decode<HotelResponse>(
  jsonString: rawJson,
  fromJson: HotelResponse.fromJson,
  tag: 'HotelResponse',
  schema: {
    'status': String,
    'data': {
      'hotels': [
        {
          'id': int,
          'hotel_name': String,
          'room_price': String,
          'total_amount': String,
        }
      ]
    }
  },
);
```

### Method 3: `validate()` — Schema validation only (CI/testing)

Returns a list of all mismatches without attempting deserialization. Useful for contract testing or CI validation.

```dart
final errors = JsonDebugger.validate(
  json: jsonMap,
  schema: {
    'status': String,
    'data': {
      'hotels': [
        {'id': int, 'hotel_name': String, 'room_price': String}
      ]
    }
  },
);

if (errors.isNotEmpty) {
  for (final e in errors) {
    print(e); // Each prints with path, expected, actual
  }
}
```

## Schema Definition

Schemas are plain Dart maps mirroring your JSON structure:

| Schema value | Meaning |
|---|---|
| `String` | Field must be a string |
| `int` | Field must be an integer |
| `double` | Field must be a number (int also accepted) |
| `bool` | Field must be a boolean |
| `num` | Field must be any number |
| `{ ... }` | Field must be an object — recurse into it |
| `[ schema ]` | Field must be an array — validate each element against `schema` |

Null values are allowed by default. Missing keys are skipped (not flagged as errors).

## Error Class

`JsonDebugError` implements `Exception` and exposes:

- **`message`** — What went wrong (`'Type mismatch'`, `'Invalid JSON syntax'`, etc.)
- **`path`** — JSON path (`'$.data.hotels[0].room_price'`)
- **`expected`** — Expected type (`'String'`)
- **`actual`** — Actual type and value (`'int (value: 12500)'`)
- **`offset`** — Character offset in raw JSON (when available)
- **`tag`** — Model name you passed in
- **`suggestions`** — Alternative locations when multiple matches are found

## When to Use Each Method

| Scenario | Method |
|---|---|
| Most projects (recommended default) | `wrap()` |
| Debugging a specific failing endpoint | `wrap()` with tag |
| Critical endpoint, want maximum precision | `decode()` with schema |
| CI/CD contract tests | `validate()` |

## License

MIT
