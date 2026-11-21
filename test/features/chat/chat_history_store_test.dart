// phase-06
// ChatHistoryStore: round-trip, 50-cap, clear-all (DPDP), no raw
// capture text.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/features/chat/chat_history_store.dart';
import 'package:udao/features/chat/chat_models.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late ChatHistoryStore store;

  setUp(() async {
    db = await helper.createTestDb();
    store = ChatHistoryStore(kv: KvDao(db.db));
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  ChatMessage msg(int i, {ChatRole role = ChatRole.ai}) => ChatMessage(
        id: 'm$i',
        role: role,
        text: 'message number $i',
        atMs: 1700000000000 + i * 1000,
        toolCalls: i == 3
            ? <ToolCallTrace>[
                const ToolCallTrace(
                  name: 'query_spends',
                  args: <String, Object?>{'category': 'food'},
                  elapsedMs: 34,
                  ok: true,
                ),
              ]
            : const <ToolCallTrace>[],
      );

  test('empty store loads an empty list', () async {
    final List<ChatMessage> loaded =
        (await store.load()).valueOrNull ?? <ChatMessage>[];
    expect(loaded, isEmpty);
  });

  test('save → load round-trip preserves fields + tool traces',
      () async {
    await store.save(<ChatMessage>[
      msg(1, role: ChatRole.user),
      msg(2),
      msg(3),
    ]);
    final List<ChatMessage> loaded =
        (await store.load()).valueOrNull ?? <ChatMessage>[];
    expect(loaded, hasLength(3));
    expect(loaded.first.role, ChatRole.user);
    expect(loaded[1].text, 'message number 2');
    expect(loaded[2].toolCalls, hasLength(1));
    expect(loaded[2].toolCalls.single.name, 'query_spends');
    expect(loaded[2].toolCalls.single.args['category'], 'food');
    expect(loaded[2].toolCalls.single.elapsedMs, 34);
    expect(loaded[2].toolCalls.single.ok, isTrue);
  });

  test('history is capped at the last 50 messages', () async {
    final List<ChatMessage> many =
        List<ChatMessage>.generate(80, (int i) => msg(i));
    await store.save(many);
    final List<ChatMessage> loaded =
        (await store.load()).valueOrNull ?? <ChatMessage>[];
    expect(loaded, hasLength(50));
    expect(loaded.first.id, 'm30');
    expect(loaded.last.id, 'm79');
  });

  test('clearAll wipes history (single key delete)', () async {
    await store.save(<ChatMessage>[msg(1)]);
    final Result<void> cleared = await store.clearAll();
    expect(cleared.isOk, isTrue);
    expect(
      (await store.load()).valueOrNull ?? <ChatMessage>[],
      isEmpty,
    );
    expect(
      (await KvDao(db.db).get(ChatHistoryStore.kvKey)).valueOrNull,
      isNull,
    );
  });

  test('tool trace preview keeps two args', () {
    const ToolCallTrace t = ToolCallTrace(
      name: 'set_budget',
      args: <String, Object?>{
        'category': 'food',
        'limit': 2000,
        'extra': 'noise',
      },
      elapsedMs: 12,
      ok: true,
    );
    expect(t.argsPreview, 'category: food, limit: 2000');
    expect(
      const ToolCallTrace(
        name: 'x',
        args: <String, Object?>{},
        elapsedMs: 1,
        ok: true,
      ).argsPreview,
      '',
    );
  });
}
