// phase-06
// Chat-domain models. History is capped and kv-backed (DPDP
// clear-all friendly); roasts ALSO land in roast_entry (Phase-02
// table) for freshness rotation + "roast of the month".
class ToolCallTrace {
  const ToolCallTrace({
    required this.name,
    required this.args,
    required this.elapsedMs,
    required this.ok,
  });

  final String name;
  final Map<String, Object?> args;
  final int elapsedMs;
  final bool ok;

  /// Compact arg preview for the chip ("category: khaana").
  String get argsPreview {
    if (args.isEmpty) {
      return '';
    }
    final List<String> parts = <String>[];
    for (final MapEntry<String, Object?> e in args.entries.take(2)) {
      parts.add('${e.key}: ${e.value}');
    }
    return parts.join(', ');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'args': args,
        'ms': elapsedMs,
        'ok': ok,
      };

  static ToolCallTrace fromJson(Map<Object?, Object?> json) =>
      ToolCallTrace(
        name: json['name'] as String? ?? '',
        args: Map<String, Object?>.from(json['args'] as Map? ?? <String, Object?>{}),
        elapsedMs: json['ms'] as int? ?? 0,
        ok: json['ok'] as bool? ?? false,
      );
}

enum ChatRole { user, ai }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.atMs,
    this.toolCalls = const <ToolCallTrace>[],
    this.guarded = false,
    this.personaId,
    this.capped = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final int atMs;
  final List<ToolCallTrace> toolCalls;
  final bool guarded;

  /// Which persona answered (rendered as the bubble's accent).
  final String? personaId;

  /// True when the 5-round cap ended the turn (honesty chip).
  final bool capped;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'role': role.name,
        'text': text,
        'atMs': atMs,
        'tools': toolCalls.map((ToolCallTrace t) => t.toJson()).toList(),
        'guarded': guarded,
        'persona': personaId,
        'capped': capped,
      };

  static ChatMessage fromJson(Map<Object?, Object?> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        role: json['role'] == 'user' ? ChatRole.user : ChatRole.ai,
        text: json['text'] as String? ?? '',
        atMs: json['atMs'] as int? ?? 0,
        toolCalls: ((json['tools'] as List?) ?? <Object?>[])
            .map(
              (Object? t) => ToolCallTrace.fromJson(t! as Map),
            )
            .toList(growable: false),
        guarded: json['guarded'] as bool? ?? false,
        personaId: json['persona'] as String?,
        capped: json['capped'] as bool? ?? false,
      );
}
