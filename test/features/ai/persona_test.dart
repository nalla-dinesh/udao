// phase-06
// Personas (4, with sampling + surfaces) + the router (stress
// override, pin-wins, 72h window).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/features/ai/persona/persona.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/features/ai/persona/persona_router.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('persona catalog', () {
    test('four personas with stable ids', () {
      expect(Personas.savage.id, 'savage');
      expect(Personas.hype.id, 'hype');
      expect(Personas.silent.id, 'silent');
      expect(Personas.sensei.id, 'sensei');
      expect(Personas.byId('savage'), Personas.savage);
      expect(
        Personas.byId('bogus'),
        Personas.savage,
        reason: 'unknown id falls back to the default',
      );
    });

    test('sampling: savage hot, silent cold, hype warm, sensei mid',
        () {
      expect(Personas.savage.temperature, greaterThan(0.85));
      expect(
        Personas.hype.temperature,
        allOf(greaterThan(Personas.sensei.temperature), lessThan(1)),
      );
      expect(Personas.silent.temperature, lessThan(0.5));
      expect(Personas.silent.topK, lessThan(Personas.savage.topK));
    });

    test('every persona carries a system prompt + voice note', () {
      for (final Persona p in Personas.all) {
        expect(p.systemPrompt.length, greaterThan(20));
        expect(p.voiceNote, isNotEmpty);
        expect(p.allowedSurfaces, isNotEmpty);
      }
    });

    test('savage is roast-tagged; sensei is not', () {
      expect(Personas.savage.templateTag, 'roast');
      expect(Personas.sensei.templateTag, isNot('roast'));
    });
  });

  group('PersonaRouter (kv on real DB)', () {
    late UdaoDatabase db;
    late KvDao kv;
    final DateTime t0 = DateTime(2026, 10, 30, 10);

    setUp(() async {
      db = await helper.createTestDb();
      kv = KvDao(db.db);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });
    tearDown(() async {
      await helper.disposeTestDb(db);
    });

    test('no stress, no pin → base persona', () async {
      final PersonaRouter r = PersonaRouter(kv: kv, clock: () => t0);
      final ResolvedPersona p = await r.resolve();
      expect(p.persona, Personas.savage);
      expect(p.stressOverride, isFalse);
    });

    test('active stress window → sensei override', () async {
      final PersonaRouter r = PersonaRouter(kv: kv, clock: () => t0);
      await r.onStressDetected();
      final ResolvedPersona p = await r.resolve();
      expect(p.persona, Personas.sensei);
      expect(p.stressOverride, isTrue);
      expect(
        p.stressUntilMs - t0.millisecondsSinceEpoch,
        closeTo(72 * 60 * 60 * 1000, 1000),
      );
    });

    test('expired stress window → base persona again', () async {
      final PersonaRouter past = PersonaRouter(
        kv: kv,
        clock: () => t0.subtract(const Duration(hours: 73)),
      );
      await past.onStressDetected();
      final PersonaRouter r = PersonaRouter(kv: kv, clock: () => t0);
      final ResolvedPersona p = await r.resolve();
      expect(p.persona, Personas.savage);
      expect(p.stressOverride, isFalse);
    });

    test('pin beats stress (manual override is king)', () async {
      final PersonaRouter r = PersonaRouter(kv: kv, clock: () => t0);
      await r.setPersona('hype', pinned: true);
      await r.onStressDetected();
      final ResolvedPersona p = await r.resolve();
      expect(p.persona, Personas.hype);
      expect(p.stressOverride, isFalse);
    });

    test('clearStress ends the window immediately', () async {
      final PersonaRouter r = PersonaRouter(kv: kv, clock: () => t0);
      await r.onStressDetected();
      await r.clearStress();
      expect((await r.resolve()).persona, Personas.savage);
    });

    test('setPersona(pinned:false) does not pin', () async {
      final PersonaRouter r = PersonaRouter(kv: kv, clock: () => t0);
      await r.setPersona('silent', pinned: false);
      await r.onStressDetected();
      expect((await r.resolve()).persona, Personas.sensei);
    });
  });
}
