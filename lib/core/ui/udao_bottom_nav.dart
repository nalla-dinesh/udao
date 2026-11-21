// phase-01
// UdaoBottomNav — 5-destination custom bottom navigation with a
// spring-sliding flame pill indicator and badge counts.
// Fully custom: no Material NavigationBar anywhere.
import 'package:flutter/material.dart';

import '../theme/udao_motion.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'app_svg.dart';
import 'haptics.dart';

/// One nav destination: a brand SVG mark and/or a Phosphor glyph.
class UdaoNavItem {
  const UdaoNavItem({required this.label, this.svgAsset, this.iconData})
      : assert(
          (svgAsset == null) != (iconData == null),
          'exactly one of svgAsset / iconData must be set',
        );

  final String label;
  final String? svgAsset;
  final IconData? iconData;
}

class UdaoBottomNav extends StatelessWidget {
  const UdaoBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.badges,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<UdaoNavItem> items;

  /// Destination index → pending-count badge (hidden when 0/absent).
  final Map<int, int>? badges;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;
    final int count = items.length;
    final double pillAlignmentX =
        -1.0 + 2.0 * (currentIndex + 0.5) / count;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: sem.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            children: <Widget>[
              AnimatedAlign(
                duration: UdaoMotion.base,
                curve: UdaoMotion.spring,
                alignment: Alignment(pillAlignmentX, 0),
                child: Container(
                  width: 56,
                  height: 36,
                  decoration: BoxDecoration(
                    color: sem.flame.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(UdaoRadius.pill),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < count; i++)
                    Expanded(
                      child: _NavDestination(
                        item: items[i],
                        selected: i == currentIndex,
                        badge: badges?[i] ?? 0,
                        onTap: () {
                          UdaoHaptics.tap();
                          onTap(i);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavDestination extends StatelessWidget {
  const _NavDestination({
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final UdaoNavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;
    final Color color =
        selected ? sem.flame : scheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (item.svgAsset != null)
                  AppSvg(
                    item.svgAsset!,
                    width: 24,
                    height: 24,
                    color: color,
                  )
                else
                  Icon(item.iconData, size: 24, color: color),
                if (badge > 0)
                  Positioned(
                    right: -10,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sem.flame,
                        borderRadius: BorderRadius.circular(UdaoRadius.pill),
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: text.labelSmall?.copyWith(
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.label.toUpperCase(),
              style: text.labelSmall?.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
