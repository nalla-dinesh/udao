// phase-05
// WatchdogPlanner — the PURE-Dart spec of the Kotlin HealthPinger
// recovery ladder. Same inputs (listener flags + clock + cooldown
// state), same outputs (ordered actions). The Kotlin worker is the
// executor; this planner is what the dashboard EXPLAINS and what the
// unit tests pin down. If you change one, change both (see
// android/.../capture/HealthPinger.kt).
//
// This file deliberately performs no IO and no sleeps — it maps a
// snapshot of flags to the action sequence the native side takes.
import 'package:flutter/foundation.dart';

import 'survival_models.dart';

/// One rung of the recovery ladder.
enum WatchdogPlanAction {
  /// Nothing needed — listener was healthy.
  none,

  /// requestRebind issued.
  rebind,

  /// 5s latch wait (both after rebind and after toggle).
  wait,

  /// Component disable+re-enable workaround issued.
  toggle,

  /// High-priority notification posted.
  escalate,

  /// Escalation skipped — inside the 24h cooldown.
  suppressed,
}

@immutable
class WatchdogInput {
  const WatchdogInput({
    required this.nowMs,
    required this.listenerConnected,
    required this.lastEscalatedAt,
    this.rebindLatchMs = 5000,
    this.escalationCooldownMs = 24 * 60 * 60 * 1000,
  });

  final int nowMs;
  final bool listenerConnected;
  final int lastEscalatedAt;

  /// HealthPinger.REBIND_LATCH_MS mirror.
  final int rebindLatchMs;

  /// HealthPinger.ESCALATION_COOLDOWN_MS mirror.
  final int escalationCooldownMs;
}

@immutable
class WatchdogPlan {
  const WatchdogPlan({required this.actions, required this.recovered});

  /// Ordered actions for one run (collapsed waits included).
  final List<WatchdogPlanAction> actions;

  /// True when the ladder ended with the listener healthy.
  final bool recovered;
}

/// The state machine (input flags → expected action sequence).
class WatchdogPlanner {
  const WatchdogPlanner();

  /// Plans the ladder for ONE 30-min run, given the flags observed
  /// at entry and the (simulated) outcomes of each rung. The caller
  /// supplies `simulate` to answer "did the binding come back?"
  /// after each wait — in production that is the async truth; here
  /// it keeps the planner pure.
  WatchdogPlan plan(
    WatchdogInput input, {
    required bool Function() afterRebindReconnected,
    bool Function()? afterToggleReconnected,
  }) {
    final List<WatchdogPlanAction> actions = <WatchdogPlanAction>[];
    if (input.listenerConnected) {
      return const WatchdogPlan(
        actions: <WatchdogPlanAction>[WatchdogPlanAction.none],
        recovered: true,
      );
    }
    actions.add(WatchdogPlanAction.rebind);
    actions.add(WatchdogPlanAction.wait);
    if (afterRebindReconnected()) {
      return WatchdogPlan(actions: actions, recovered: true);
    }
    actions.add(WatchdogPlanAction.toggle);
    actions.add(WatchdogPlanAction.wait);
    final bool afterToggle =
        afterToggleReconnected == null ? false : afterToggleReconnected();
    if (afterToggle) {
      return WatchdogPlan(actions: actions, recovered: true);
    }
    final bool inCooldown =
        input.nowMs - input.lastEscalatedAt < input.escalationCooldownMs;
    actions.add(inCooldown ? WatchdogPlanAction.suppressed : WatchdogPlanAction.escalate);
    return WatchdogPlan(actions: actions, recovered: false);
  }

  /// The dashboard's plain-language trace of what the pinger DID on
  /// its last run (slugs from HealthPinger's persisted snapshot).
  static String explainLastRun(WatchdogSnapshot snapshot) {
    return switch (snapshot.lastAction) {
      'none' => 'Sab theek tha — koi action nahi',
      'rebind' => 'Listener gir gaya tha — rebind se wapas aa gaya',
      'toggle' => 'Rebind kaam nahi kiya — component toggle se theek hua',
      'escalated' => 'Dono kaam nahi kiye — notification bheja gaya',
      'suppressed' => 'Dono kaam nahi kiye — 24 ghante ka cooldown chal raha hai',
      _ => 'Pehla run baaki hai',
    };
  }

  /// Dashboard stamp from the live listener + last-event age.
  static HealthVerdict verdict({
    required bool listenerConnected,
    required int lastEventAt,
    required int nowMs,
  }) {
    if (!listenerConnected) {
      return HealthVerdict.dead;
    }
    final int ageMs = nowMs - lastEventAt;
    // 24h+ bina kisi event ke = listener juda hai par kaam nahi kar
    // raha — watch. (lastEventAt 0 = abhi kuch capture nahi hua, that
    // is fresh-install, not dead — but we stay honest and say watch.)
    if (lastEventAt > 0 && ageMs > 24 * 60 * 60 * 1000) {
      return HealthVerdict.watch;
    }
    return HealthVerdict.sharp;
  }
}
