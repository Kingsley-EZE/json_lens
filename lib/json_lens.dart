/// Kotlin-like precision for JSON deserialization errors in Dart.
///
/// Instead of the unhelpful `type 'int' is not a subtype of type 'String'`,
/// json_lens gives you the exact JSON path, expected type, actual type,
/// and the value that caused the failure.
///
/// Three ways to use it:
///
/// 1. **`JsonDebugger.wrap()`** — Wrap existing fromJson in one line (recommended default)
/// 2. **`JsonDebugger.decode()`** — Full decode with schema validation (best precision)
/// 3. **`JsonDebugger.validate()`** — Schema-only validation, returns list of errors (CI/testing)
library json_lens;

export 'src/json_debugger.dart' show JsonDebugger, JsonDebugError;
