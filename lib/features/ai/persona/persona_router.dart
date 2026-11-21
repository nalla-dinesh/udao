// phase-06
// Which persona speaks right now. Base = the user's pick (onboarding
// or settings); a stress detection forces Sensei for 72h UNLESS the
// user pinned a persona explicitly (manual override is king).
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/result/result.dart';
import '../../../core/storage/local_prefs.dart';
import '../../../data/db/dao/kv_dao.dart';
import 'persona.dart';

class ResolvedPersona {
  const ResolvedPersona({
    required this.persona,
    required this.stressOverride,
    required this.stressUntilMs,
  });

  final Persona persona;
  final bool stressOverride;
  final int stressUntilMs;
}

class PersonaRouter {
  PersonaRouter({
    required KvDao kv,
    DateTime Function() clock = DateTime.now,
  })  : _kv = kv,
        _clock = clock;

  final KvDao _kv;
  final DateTime Function() _clock;

  static const String kvStressUntil = 'ai.stress.untilMs';
  static const String kvPinned = 'ai.persona.pinned';

  /// 72h Sensei window (spec).
  static const int stressWindowMs = 72 * 60 * 60 * 1000;

  Future<ResolvedPersona> resolve() async {
    final String baseId = await LocalPrefs.personality();
    final Persona base = Personas.byId(baseId);
    final Result<String?> pinned = await _kv.get(kvPinned);
    final bool isPinned = pinned.valueOrNull == '1';
    if (isPinned) {
      return ResolvedPersona(
        persona: base,
        stressOverride: false,
        stressUntilMs: 0,
      );
    }
    final Result<String?> raw = await _kv.get(kvStressUntil);
    final int untilMs = int.tryParse(raw.valueOrNull ?? '') ?? 0;
    final int nowMs = _clock().millisecondsSinceEpoch;
    if (untilMs > nowMs) {
      return ResolvedPersona(
        persona: Personas.sensei,
        stressOverride: true,
        stressUntilMs: untilMs,
      );
    }
    return ResolvedPersona(
      persona: base,
      stressOverride: false,
      stressUntilMs: 0,
    );
  }

  /// Explicit user choice (settings picker / onboarding).
  Future<void> setPersona(String id, {required bool pinned}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalPrefs.personalityKey, id);
    await _kv.set(kvPinned, pinned ? '1' : '0');
  }

  /// Called when the stress detector fires.
  Future<void> onStressDetected() async {
    final int nowMs = _clock().millisecondsSinceEpoch;
    await _kv.set(kvStressUntil, (nowMs + stressWindowMs).toString());
  }

  /// "Wapas savage chahiye" — clears the window, keeps the base.
  Future<void> clearStress() async {
    await _kv.delete(kvStressUntil);
  }
}
