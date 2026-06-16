## 0.0.1

- Initial release.
- `JsonDebugger.wrap()` — wrap existing `fromJson` with better error reporting (recommended default).
- `JsonDebugger.decode()` — full decode with schema validation.
- `JsonDebugger.validate()` — schema-only validation returning a list of errors.
- `JsonDebugError` exception class with formatted output showing path, expected/actual types, and values.
- Deep scanning to locate type mismatches when no schema is provided.
- Support for nested objects, arrays, and mixed structures.
