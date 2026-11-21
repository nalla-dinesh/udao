// phase-06
// kv-backed chat history: capped at 50 messages, clear-all is a
// single key delete (DPDP). No raw capture text ever lands here —
// only what the user typed and what the app answered.
import 'dart:convert';

import '../../core/result/result.dart';
import '../../data/db/dao/kv_dao.dart';
import 'chat_models.dart';

class ChatHistoryStore {
  ChatHistoryStore({required KvDao kv}) : _kv = kv;

  final KvDao _kv;

  static const String kvKey = 'ai.chat.history';
  static const int cap = 50;

  Future<Result<List<ChatMessage>>> load() async {
    final Result<String?> raw = await _kv.get(kvKey);
    final String? json = raw.valueOrNull;
    if (json == null || json.isEmpty) {
      return const Ok<List<ChatMessage>>(<ChatMessage>[]);
    }
    try {
      final List<Object?> decoded = jsonDecode(json) as List<Object?>;
      return Ok<List<ChatMessage>>(
        decoded
            .map((Object? e) => ChatMessage.fromJson(e! as Map))
            .toList(growable: false),
      );
    } on FormatException {
      // Corrupt history is survivable: start fresh, never crash chat.
      return const Ok<List<ChatMessage>>(<ChatMessage>[]);
    }
  }

  Future<Result<void>> save(List<ChatMessage> messages) async {
    final List<ChatMessage> capped =
        messages.length > cap ? messages.sublist(messages.length - cap) : messages;
    return _kv.set(
      kvKey,
      jsonEncode(capped.map((ChatMessage m) => m.toJson()).toList()),
    );
  }

  Future<Result<void>> clearAll() => _kv.delete(kvKey);
}
