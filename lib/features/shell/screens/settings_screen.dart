// phase-01
// Settings — Phase-01 stub: theme showcase entry (debug/SHOWCASE
// builds only) + version row. Real settings arrive in Phase 07.
// Phase-03: CAPTURE card with LIVE listener status (health provider
// polls on resume + 60s) that pushes the permission gate.
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/routes.dart';
import '../../../core/platform/app_flavor.dart';
import '../../../core/theme/udao_spacing.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/app_svg.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/ui/udao_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../capture/bridge/listener_status.dart';
import '../../capture/capture_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// The showcase ships in debug builds and in release builds started
  /// with `--dart-define=SHOWCASE=true` — normal store installs never
  /// see it.
  static bool get showcaseAvailable =>
      kDebugMode || const bool.fromEnvironment('SHOWCASE');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final ListenerStatus? status =
        ref.watch(listenerHealthProvider).valueOrNull;

    // Phase-04: SMS tile is power-only — fail-closed on unknown.
    final AsyncValue<AppFlavor> flavor = ref.watch(appFlavorProvider);
    final bool powerBuild = flavor.valueOrNull == AppFlavor.power;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(UdaoSpacing.lg),
          children: <Widget>[
            const SectionHeader(number: '01', label: 'SETTINGS'),
            UdaoCard(
              onTap: () {
                unawaited(context.push(Routes.captureGate));
              },
              child: Row(
                children: <Widget>[
                  AppSvg(
                    AppIcons.jar,
                    width: 32,
                    height: 32,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: UdaoSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.settingsCaptureTile,
                          style: text.titleMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: UdaoSpacing.xs),
                        Text(
                          status?.granted == true
                              ? l10n.settingsCaptureOn
                              : l10n.settingsCaptureOff,
                          style: text.bodySmall?.copyWith(
                            color: status?.granted == true
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: UdaoSpacing.md,
                    height: UdaoSpacing.md,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status?.granted == true
                          ? scheme.primary
                          : scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: UdaoSpacing.xl),
            SectionHeader(
              number: '02',
              label: l10n.settingsToolsSection.toUpperCase(),
            ),
            UdaoCard(
              onTap: () {
                unawaited(context.push(Routes.importStatement));
              },
              child: Row(
                children: <Widget>[
                  AppSvg(
                    AppIcons.jar,
                    width: 32,
                    height: 32,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: UdaoSpacing.lg),
                  Expanded(
                    child: Text(
                      l10n.settingsImportTile,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            UdaoCard(
              onTap: () {
                unawaited(context.push(Routes.gap));
              },
              child: Row(
                children: <Widget>[
                  AppSvg(
                    AppIcons.verdictBell,
                    width: 32,
                    height: 32,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: UdaoSpacing.lg),
                  Expanded(
                    child: Text(
                      l10n.settingsGapTile,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // phase-06: on-device AI settings (model import, tiers,
            // personas, learned patterns, telemetry).
            UdaoCard(
              onTap: () {
                unawaited(context.push(Routes.aiSettings));
              },
              child: Row(
                children: <Widget>[
                  Icon(
                    PhosphorIconsBold.brain,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: UdaoSpacing.lg),
                  Expanded(
                    child: Text(
                      l10n.settingsAiTile,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // phase-05: capture-health dashboard (stamps, watchdog
            // trace, keep-alive, device truth, diagnostics export).
            UdaoCard(
              onTap: () {
                unawaited(context.push(Routes.healthDashboard));
              },
              child: Row(
                children: <Widget>[
                  AppSvg(
                    AppIcons.streakFlame,
                    width: 32,
                    height: 32,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: UdaoSpacing.lg),
                  Expanded(
                    child: Text(
                      l10n.settingsHealthTile,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (powerBuild)
              UdaoCard(
                onTap: () {
                  unawaited(context.push(Routes.smsGate));
                },
                child: Row(
                  children: <Widget>[
                    AppSvg(
                      AppIcons.logoMark,
                      width: 32,
                      height: 32,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: UdaoSpacing.lg),
                    Expanded(
                      child: Text(
                        l10n.settingsSmsTile,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (showcaseAvailable)
              UdaoCard(
                onTap: () {
                  unawaited(context.push(Routes.showcase));
                },
                child: Row(
                  children: <Widget>[
                    AppSvg(
                      AppIcons.logoMark,
                      width: 32,
                      height: 32,
                      color: scheme.onSurface,
                    ),
                    const SizedBox(width: UdaoSpacing.lg),
                    Expanded(
                      child: Text(
                        l10n.settingsShowcaseTile,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      'DEBUG',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            UdaoCard(
              child: Row(
                children: <Widget>[
                  AppSvg(
                    AppIcons.roastFlame,
                    width: 32,
                    height: 32,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: UdaoSpacing.lg),
                  Expanded(
                    child: Text(
                      l10n.settingsVersion,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
