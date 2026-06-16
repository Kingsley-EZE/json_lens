## 0.0.2

- Added `logOnError` parameter to `JsonDebugger.wrap()` and `JsonDebugger.decode()` (defaults to `true`).
- Errors are now automatically logged to the console via `dart:developer` before throwing, so they're visible even when caught upstream.

## 0.0.1

- Initial release.
- `JsonDebugger.wrap()` — wrap existing `fromJson` with better error reporting (recommended default).
- `JsonDebugger.decode()` — full decode with schema validation.
- `JsonDebugger.validate()` — schema-only validation returning a list of errors.
- `JsonDebugError` exception class with formatted output showing path, expected/actual types, and values.
- Deep scanning to locate type mismatches when no schema is provided.
- Support for nested objects, arrays, and mixed structures.
