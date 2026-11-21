// phase-06
// The tool contract the agent loop speaks. Schemas are plain
// JSON-ish maps (Dart-side constrained parsing — no native function
// calling SDK dependency, by design).
abstract class AgentTool {
  /// Stable snake_case name the model calls it by.
  String get name;

  /// One-line description for the system prompt.
  String get description;

  /// Argument schema: name → {'type': 'string'|'number'|'boolean',
  /// 'required': bool, 'enum': [...]?}. Validated BEFORE invoke.
  Map<String, Map<String, Object?>> get schema;

  /// Runs the tool. NEVER throws — an error is {'ok': false,
  /// 'error': '...'} and the model is told, honestly.
  Future<Map<String, Object?>> invoke(Map<String, Object?> args);
}

/// Validation result for a tool-call's arguments.
class ToolSchemaIssue {
  const ToolSchemaIssue(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class ToolSchema {
  /// Validates [args] against [tool.schema]: unknown keys are
  /// tolerated (models add noise), missing required keys and type
  /// mismatches are not.
  static ToolSchemaIssue? validate(
    AgentTool tool,
    Map<String, Object?> args,
  ) {
    final Map<String, Map<String, Object?>> schema = tool.schema;
    for (final MapEntry<String, Map<String, Object?>> entry
        in schema.entries) {
      final String key = entry.key;
      final Map<String, Object?> spec = entry.value;
      final bool required = spec['required'] == true;
      final Object? value = args[key];
      if (value == null) {
        if (required) {
          return ToolSchemaIssue('$key is required');
        }
        continue;
      }
      final String expected = spec['type'] as String? ?? 'string';
      final bool ok = switch (expected) {
        'string' => value is String,
        'number' => value is num,
        'boolean' => value is bool,
        _ => true,
      };
      if (!ok) {
        return ToolSchemaIssue('$key must be a $expected');
      }
      final Object? allowed = spec['enum'];
      if (allowed is List && value is String && !allowed.contains(value)) {
        final String oneOf = allowed.join('|');
        return ToolSchemaIssue(
          '$key must be one of $oneOf',
        );
      }
    }
    return null;
  }
}
