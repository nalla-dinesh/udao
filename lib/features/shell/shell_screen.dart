// phase-01
// App shell — custom bottom nav (5 branches) hosting the indexed
// StatefulShellRoute. Re-tapping the active tab pops to that branch's
// root (go_router convention).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/ui/app_icons.dart';
import '../../core/ui/udao_bottom_nav.dart';
import '../../l10n/app_localizations.dart';

class ShellScreen extends StatelessWidget {
  const ShellScreen({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: UdaoBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (int index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: <UdaoNavItem>[
          UdaoNavItem(
            label: l10n.navAaj,
            svgAsset: AppIcons.roastFlame,
          ),
          UdaoNavItem(
            label: l10n.navChat,
            iconData: PhosphorIconsBold.chatCircle,
          ),
          UdaoNavItem(
            label: l10n.navKhel,
            svgAsset: AppIcons.ladder,
          ),
          UdaoNavItem(
            label: l10n.navLedger,
            iconData: PhosphorIconsBold.receipt,
          ),
          UdaoNavItem(
            label: l10n.navSettings,
            iconData: PhosphorIconsBold.gearSix,
          ),
        ],
      ),
    );
  }
}
