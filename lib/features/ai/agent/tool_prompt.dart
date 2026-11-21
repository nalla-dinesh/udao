// phase-06
// The system prompt: EN scaffolding (instruction following) +
// Hinglish answer law. Tool schemas are rendered from the SAME
// [AgentTool] objects the loop validates against — the prompt and
// the validator can never drift (pinned by tests).
import 'agent_tool.dart';

abstract final class ToolPrompt {
  /// Deterministic system prompt for the agent loop.
  static String build({
    required List<AgentTool> tools,
    required String context,
    required String personaPrompt,
  }) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(personaPrompt);
    buffer.write('\n\n');
    buffer.write(_answerRules);
    buffer.write('\n\nWALLET CONTEXT:\n');
    buffer.write(context);
    buffer.write('\n\nTOOLS — to call one, reply with ONLY this JSON '
        'object and nothing else:\n'
        '{"tool": "<name>", "args": {<arguments>}}\n'
        'After each call you receive a TOOL_RESULT message with the '
        'outcome. When you have the answer (or need no tool), reply '
        'in plain Hinglish text — NO JSON.\n\n');
    for (final AgentTool tool in tools) {
      buffer.write('${tool.name}: ${tool.description}\n');
      buffer.write('  args: ${_schemaJson(tool)}\n');
    }
    buffer.write(
      '\nHard rules:\n'
      '- Maximum $maxToolRounds tool rounds; after that answer with '
      'what you have.\n'
      '- Never invent transactions or numbers — only report what '
      'tools return.\n'
      '- If a tool errors, say so honestly.\n',
    );
    return buffer.toString();
  }

  /// Max tool rounds before the loop stops offering tools (the loop
  /// itself hard-caps at 5 iterations — same constant, one source).
  static const int maxToolRounds = 5;

  static const String _answerRules = 'ANSWER RULES:\n'
      '- Reply in natural Hinglish (Roman script), like a sharp '
      'Indian friend.\n'
      '- Money in Rs. numbers (Rs.1250). Dates dd MMM.\n'
      '- Keep it short — 1-3 lines unless detail is asked.\n'
      '- Never invent transactions — only report what tools return.\n'
      '- If a tool errors, say so honestly.';

  /// Compact single-line schema rendering (stable order).
  static String _schemaJson(AgentTool tool) {
    if (tool.schema.isEmpty) {
      return '{}';
    }
    final List<String> parts = <String>[];
    for (final MapEntry<String, Map<String, Object?>> entry
        in tool.schema.entries) {
      final Map<String, Object?> spec = entry.value;
      final String type = spec['type'] as String? ?? 'string';
      final Object? allowed = spec['enum'];
      final String req = spec['required'] == true ? '' : '?';
      final String tail = allowed is List ? allowed.join('|') : type;
      parts.add('${entry.key}$req: $tail');
    }
    final String body = parts.join(', ');
    return '{$body}';
  }

  /// The repair prompt for a malformed/invalid tool call (retry
  /// ONCE, then the loop treats the text as the final answer).
  static String repairPrompt(String problem) =>
      'Your last message was meant as a tool call but it was invalid: '
      '$problem\n'
      'Reply again with ONLY the JSON object '
      '{"tool": "<name>", "args": {…}} — no prose, no markdown.';
}
