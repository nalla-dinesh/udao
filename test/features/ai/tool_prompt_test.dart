// phase-06
// ToolPrompt: prompt/validator single-source laws.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/ai/agent/agent_tool.dart';
import 'package:udao/features/ai/agent/tool_prompt.dart';
import 'package:udao/features/ai/persona/persona.dart';

class _DemoTool extends AgentTool {
  @override
  String get name => 'demo_tool';

  @override
  String get description => 'demo';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{
        'category': <String, Object?>{
          'type': 'string',
          'required': true,
          'enum': <String>['food', 'shopping'],
        },
        'limit': <String, Object?>{'type': 'number'},
        'force': <String, Object?>{'type': 'boolean'},
      };

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async =>
      <String, Object?>{'ok': true};
}

void main() {
  test('prompt carries persona, rules, context, tool + schema', () {
    final String prompt = ToolPrompt.build(
      tools: <AgentTool>[_DemoTool()],
      context: 'CTX-MARKER',
      personaPrompt: Personas.savage.systemPrompt,
    );
    expect(prompt, contains('CTX-MARKER'));
    expect(prompt, contains('demo_tool: demo'));
    expect(prompt, contains('category: food|shopping'));
    expect(prompt, contains('limit?: number'));
    expect(prompt, contains('force?: boolean'));
    expect(prompt, contains('Hinglish'));
    expect(prompt, contains('Never invent transactions'));
    expect(prompt, contains('TOOL_RESULT'));
  });

  test('maxToolRounds is 5 (loop cap shares this constant)', () {
    expect(ToolPrompt.maxToolRounds, 5);
  });

  test('repair prompt names the problem and the JSON shape', () {
    final String r = ToolPrompt.repairPrompt('category is required');
    expect(r, contains('category is required'));
    expect(r, contains('{"tool": "<name>", "args": {…}}'));
  });

  test('ToolSchema: missing required rejected', () {
    expect(
      ToolSchema.validate(_DemoTool(), <String, Object?>{}),
      isNotNull,
    );
  });

  test('ToolSchema: type mismatch rejected', () {
    expect(
      ToolSchema.validate(
        _DemoTool(),
        <String, Object?>{'category': 'food', 'limit': 'lots'},
      ),
      isNotNull,
    );
  });

  test('ToolSchema: enum violation rejected with the allowed list',
      () {
    final ToolSchemaIssue? issue = ToolSchema.validate(
      _DemoTool(),
      <String, Object?>{'category': 'travel'},
    );
    expect(issue, isNotNull);
    expect(issue.toString(), contains('food|shopping'));
  });

  test('ToolSchema: valid args pass, unknown extra keys tolerated',
      () {
    expect(
      ToolSchema.validate(_DemoTool(), <String, Object?>{
        'category': 'food',
        'limit': 500,
        'force': true,
        'modelNoise': 'whatever',
      }),
      isNull,
    );
  });

  test('ToolSchema: optional missing is fine', () {
    expect(
      ToolSchema.validate(_DemoTool(), <String, Object?>{'category': 'food'}),
      isNull,
    );
  });
}
