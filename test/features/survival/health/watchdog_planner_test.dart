// phase-05
// The watchdog state machine, pinned in pure Dart. This is the spec
// the Kotlin HealthPinger executes (rebind → 5s wait → toggle →
// 5s wait → escalate with a 24h cooldown); both must stay in sync.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/survival/health/survival_models.dart';
import 'package:udao/features/survival/health/watchdog_planner.dart';

const int _dayMs = 24 * 60 * 60 * 1000;

void main() {
  const WatchdogPlanner planner = WatchdogPlanner();

  WatchdogPlan planWith({
    required bool connected,
    required bool afterRebind,
    bool afterToggle = false,
    int nowMs = 1000000000,
    int lastEscalatedAt = 0,
  }) {
    return planner.plan(
      WatchdogInput(
        nowMs: nowMs,
        listenerConnected: connected,
        lastEscalatedAt: lastEscalatedAt,
      ),
      afterRebindReconnected: () => afterRebind,
      afterToggleReconnected: () => afterToggle,
    );
  }

  group('recovery ladder', () {
    test('healthy listener → single none action, recovered', () {
      final WatchdogPlan plan = planWith(connected: true, afterRebind: true);
      expect(plan.actions, const <WatchdogPlanAction>[WatchdogPlanAction.none]);
      expect(plan.recovered, isTrue);
    });

    test('down; plain rebind heals → rebind, wait', () {
      final WatchdogPlan plan = planWith(
        connected: false,
        afterRebind: true,
      );
      expect(
        plan.actions,
        const <WatchdogPlanAction>[
          WatchdogPlanAction.rebind,
          WatchdogPlanAction.wait,
        ],
      );
      expect(plan.recovered, isTrue);
    });

    test('down; rebind fails, toggle heals → rebind, wait, toggle, wait',
        () {
      final WatchdogPlan plan = planWith(
        connected: false,
        afterRebind: false,
        afterToggle: true,
      );
      expect(
        plan.actions,
        const <WatchdogPlanAction>[
          WatchdogPlanAction.rebind,
          WatchdogPlanAction.wait,
          WatchdogPlanAction.toggle,
          WatchdogPlanAction.wait,
        ],
      );
      expect(plan.recovered, isTrue);
    });

    test('down; nothing heals, no recent escalation → escalate', () {
      final WatchdogPlan plan = planWith(
        connected: false,
        afterRebind: false,
        afterToggle: false,
        nowMs: 10 * _dayMs,
        lastEscalatedAt: 0,
      );
      expect(plan.actions.last, WatchdogPlanAction.escalate);
      expect(plan.recovered, isFalse);
      expect(plan.actions, hasLength(5));
    });

    test('down; nothing heals but escalated 23h ago → suppressed (cooldown)',
        () {
      const int now = 10 * _dayMs;
      final WatchdogPlan plan = planWith(
        connected: false,
        afterRebind: false,
        afterToggle: false,
        nowMs: now,
        lastEscalatedAt: now - 23 * 60 * 60 * 1000,
      );
      expect(plan.actions.last, WatchdogPlanAction.suppressed);
      expect(plan.actions, hasLength(5));
      expect(plan.recovered, isFalse);
    });

    test('cooldown boundary: exactly 24h old escalation frees the nag', () {
      const int now = 10 * _dayMs;
      final WatchdogPlan plan = planWith(
        connected: false,
        afterRebind: false,
        afterToggle: false,
        nowMs: now,
        lastEscalatedAt: now - _dayMs,
      );
      expect(plan.actions.last, WatchdogPlanAction.escalate);
    });
  });

  group('dashboard verdict stamps', () {
    test('disconnected → dead (BAND)', () {
      expect(
        WatchdogPlanner.verdict(
          listenerConnected: false,
          lastEventAt: 1000000,
          nowMs: 2000000,
        ),
        HealthVerdict.dead,
      );
    });

    test('connected + fresh events → sharp', () {
      expect(
        WatchdogPlanner.verdict(
          listenerConnected: true,
          lastEventAt: 1000000,
          nowMs: 1000000 + 3 * 60 * 60 * 1000,
        ),
        HealthVerdict.sharp,
      );
    });

    test('connected + 25h stale events → watch (DHYAN DO)', () {
      expect(
        WatchdogPlanner.verdict(
          listenerConnected: true,
          lastEventAt: 1000000,
          nowMs: 1000000 + 25 * 60 * 60 * 1000,
        ),
        HealthVerdict.watch,
      );
    });

    test('connected + no events yet (fresh install) → sharp, not dead', () {
      expect(
        WatchdogPlanner.verdict(
          listenerConnected: true,
          lastEventAt: 0,
          nowMs: 1000000,
        ),
        HealthVerdict.sharp,
      );
    });

    test('slug stability (diagnostics contract)', () {
      expect(HealthVerdict.sharp.slug, 'sharp');
      expect(HealthVerdict.watch.slug, 'watch');
      expect(HealthVerdict.dead.slug, 'dead');
    });
  });

  group('explainLastRun (Hinglish traces)', () {
    WatchdogSnapshot snap(String action) => WatchdogSnapshot(
          lastPingAt: 123,
          lastAction: action,
          startedDown: true,
          listenerOk: true,
          lastEscalatedAt: 0,
          oemSuspect: false,
        );

    test('each slug has a trace', () {
      for (final String slug
          in <String>['none', 'rebind', 'toggle', 'escalated', 'suppressed']) {
        expect(WatchdogPlanner.explainLastRun(snap(slug)), isNotEmpty);
      }
    });

    test('unknown slug is honest about the first run', () {
      expect(
        WatchdogPlanner.explainLastRun(snap('garbage')),
        contains('Pehla run'),
      );
    });
  });
}
