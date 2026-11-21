// phase-01
// App router: onboarding → shell (5 tab branches) with an async
// redirect on the persisted onboarding flag. The redirect DECISION is
// a pure function (`udaoRedirect`) so it is unit-testable without a
// running app.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/capture/permission/listener_gate_screen.dart';
import '../../features/capture/permission/sms_gate_screen.dart';
import '../../features/capture/gap/gap_screen.dart';
import '../../features/capture/import/import_review_screen.dart';
import '../../features/chat/chat_screen.dart' as chat;
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/budget/budget_screen.dart';
import '../../features/settings/ai_settings_screen.dart';
import '../../features/settings/theme_showcase_screen.dart';
import '../../features/survival/health/health_dashboard_screen.dart';
import '../../features/survival/oem/oem_setup_flow_screen.dart';
import '../../features/shell/screens/aaj_screen.dart';

import '../../features/shell/screens/khel_screen.dart';
import '../../features/shell/screens/ledger_screen.dart';
import '../../features/shell/screens/settings_screen.dart';
import '../../features/shell/shell_screen.dart';
import '../constants/routes.dart';
import '../storage/local_prefs.dart';

/// Pure redirect decision.
///
///  * Fresh install (onboarding not done) → force `/onboarding`.
///  * Done + visiting `/onboarding` → `/aaj`.
///  * `SHOWCASE=true` dart-define + landing on `/aaj` → `/showcase`
///    (theme QA entry point).
String? udaoRedirect({
  required bool onboardingDone,
  required String location,
}) {
  if (const bool.fromEnvironment('SHOWCASE') && location == Routes.aaj) {
    return Routes.showcase;
  }
  if (!onboardingDone && location != Routes.onboarding) {
    return Routes.onboarding;
  }
  if (onboardingDone && location == Routes.onboarding) {
    return Routes.aaj;
  }
  return null;
}

GoRouter buildUdaoRouter() {
  return GoRouter(
    initialLocation: Routes.aaj,
    redirect: (BuildContext context, GoRouterState state) async {
      final bool done = await LocalPrefs.isOnboardingDone();
      return udaoRedirect(
        onboardingDone: done,
        location: state.matchedLocation,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.onboarding,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.captureGate,
        builder: (BuildContext context, GoRouterState state) =>
            const ListenerGateScreen(),
      ),
      // Registered in both flavors; the SCREEN itself fails closed
      // (renders only the honest off-card) unless the installed
      // build's flavor is `power` — and the play build contains no
      // receiver/manifest/permission to power it anyway.
      GoRoute(
        path: Routes.smsGate,
        builder: (BuildContext context, GoRouterState state) =>
            const SmsGateScreen(),
      ),
      GoRoute(
        path: Routes.healthDashboard,
        builder: (BuildContext context, GoRouterState state) =>
            const HealthDashboardScreen(),
      ),
      GoRoute(
        path: Routes.aiSettings,
        builder: (BuildContext context, GoRouterState state) =>
            const AiSettingsScreen(),
      ),
      GoRoute(
        path: Routes.oemSetup,
        builder: (BuildContext context, GoRouterState state) =>
            const OemSetupFlowScreen(),
      ),
      GoRoute(
        path: Routes.budgets,
        builder: (BuildContext context, GoRouterState state) =>
            const BudgetScreen(),
      ),
      GoRoute(
        path: Routes.importStatement,
        builder: (BuildContext context, GoRouterState state) =>
            const ImportReviewScreen(),
      ),
      GoRoute(
        path: Routes.gap,
        builder: (BuildContext context, GoRouterState state) =>
            const GapScreen(),
      ),
      GoRoute(
        path: Routes.showcase,
        builder: (BuildContext context, GoRouterState state) =>
            const ThemeShowcaseScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) =>
            ShellScreen(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.aaj,
                builder: (BuildContext context, GoRouterState state) =>
                    const AajScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.chat,
                builder: (BuildContext context, GoRouterState state) =>
                    const chat.ChatScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.khel,
                builder: (BuildContext context, GoRouterState state) =>
                    const KhelScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.ledger,
                builder: (BuildContext context, GoRouterState state) =>
                    const LedgerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.settings,
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
