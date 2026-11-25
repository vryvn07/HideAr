// The HideAr design system — Warm Beige & Dark Espresso Brown.
//
// Tactile rounded cards, soft warm surfaces, and humanist sans typography
// built for an understated, organic desktop privacy companion.

import 'package:flutter/material.dart';

abstract final class C {
  // Warm beige surfaces
  static const beige = Color(0xFFF5EFE6);
  static const sand = Color(0xFFEDE4D5);
  static const sandDeep = Color(0xFFE3D6C3);
  static const border = Color(0xFFD6C6B0);

  // Dark espresso browns
  static const espresso = Color(0xFF2C1B12);
  static const espressoDeep = Color(0xFF1A100B);
  static const roast = Color(0xFF4A3022);
  static const cocoa = Color(0xFF7A5C48);

  // Semantic accents harmonized with beige & brown
  static const caramel = Color(0xFF9E5A2A);
  static const caramelSoft = Color(0xFFF2DFCE);
  static const olive = Color(0xFF3B5E3C);
  static const oliveSoft = Color(0xFFE2EBDF);
}

/// Window geometry.
abstract final class W {
  static const Size panel = Size(440, 660);
  static const Size minimum = Size(380, 480);
}

/// Spacing scale.
abstract final class S {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 28;
  static const double x7 = 40;
}

/// Corner radii.
abstract final class R {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;
}

abstract final class F {
  static const List<String> sans = <String>[
    'Segoe UI Variable',
    'Segoe UI',
    'Inter',
    'Arial',
  ];
}

abstract final class T {
  static const caption = TextStyle(
    fontFamilyFallback: F.sans,
    fontSize: 11,
    height: 1.35,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w600,
    color: C.cocoa,
  );

  static const value = TextStyle(
    fontFamilyFallback: F.sans,
    fontSize: 13.5,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: C.espresso,
  );

  static const hero = TextStyle(
    fontFamilyFallback: F.sans,
    fontSize: 24,
    height: 1.15,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w700,
    color: C.espresso,
  );

  static const heading = TextStyle(
    fontFamilyFallback: F.sans,
    fontSize: 15.5,
    height: 1.25,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w700,
    color: C.espresso,
  );

  static const body = TextStyle(
    fontFamilyFallback: F.sans,
    fontSize: 12.5,
    height: 1.5,
    color: C.roast,
  );

  static const button = TextStyle(
    fontFamilyFallback: F.sans,
    fontSize: 13,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w600,
  );
}

/// Warm sand card with rounded corners and soft border.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.x4),
    this.color = C.sand,
    this.borderColor = C.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

/// Compact rounded bento tile for status metrics.
class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.toneColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final Color? toneColor;

  @override
  Widget build(BuildContext context) {
    final Color badgeBg = toneColor ?? C.sandDeep;
    final Color badgeFg = valueColor ?? C.espresso;
    return Container(
      padding: const EdgeInsets.all(S.x3),
      decoration: BoxDecoration(
        color: C.sand,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 14, color: badgeFg),
              ),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  label,
                  style: T.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(
            value,
            style: T.value.copyWith(color: valueColor ?? C.espresso),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Smooth pill progress bar replacing segmented blocks.
class VeilProgressBar extends StatelessWidget {
  const VeilProgressBar({
    super.key,
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: LinearProgressIndicator(
        value: clamped,
        minHeight: 7,
        backgroundColor: C.beige.withValues(alpha: 0.22),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Rounded tactile action button.
class ActionPillButton extends StatelessWidget {
  const ActionPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.tonal = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool tonal;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color bg =
        danger
            ? C.caramel
            : (primary ? C.espresso : (tonal ? C.sandDeep : C.beige));
    final Color fg = (primary || danger) ? C.beige : C.espresso;
    final Color borderColor =
        (primary || danger) ? Colors.transparent : C.border;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(R.md),
          hoverColor:
              (primary || danger)
                  ? C.roast
                  : C.sandDeep.withValues(alpha: 0.8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: S.x4,
              vertical: S.x3 + 1,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: S.x2),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: T.button.copyWith(color: fg),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark espresso header bar with rounded pill controls.
class HideArHeader extends StatelessWidget {
  const HideArHeader({
    super.key,
    required this.title,
    this.badgeText,
    this.badgeDotColor,
    this.onBack,
    this.onMinimise,
    this.onClose,
    this.onDragStart,
  });

  final String title;
  final String? badgeText;
  final Color? badgeDotColor;
  final VoidCallback? onBack;
  final VoidCallback? onMinimise;
  final VoidCallback? onClose;
  final VoidCallback? onDragStart;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        decoration: const BoxDecoration(
          color: C.espresso,
          border: Border(bottom: BorderSide(color: C.roast)),
        ),
        child: Row(
          children: [
            if (onBack != null) ...[
              _HeaderCircleButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: onBack!,
              ),
              const SizedBox(width: S.x2),
            ] else ...[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: C.beige,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.visibility_off_rounded,
                  size: 16,
                  color: C.espresso,
                ),
              ),
              const SizedBox(width: S.x2 + 2),
            ],
            Expanded(
              child: Text(
                title,
                style: T.heading.copyWith(color: C.beige, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badgeText != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.x2 + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: C.roast,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgeDotColor != null) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: badgeDotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      badgeText!,
                      style: T.caption.copyWith(color: C.beige, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.x2),
            ],
            if (onMinimise != null) ...[
              _HeaderCircleButton(
                icon: Icons.horizontal_rule_rounded,
                tooltip: 'Minimise to tray',
                onTap: onMinimise!,
              ),
              const SizedBox(width: 6),
            ],
            if (onClose != null)
              _HeaderCircleButton(
                icon: Icons.close_rounded,
                tooltip: 'Exit',
                onTap: onClose!,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: C.roast.withValues(alpha: 0.75),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          hoverColor: C.caramel,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 15, color: C.beige),
          ),
        ),
      ),
    );
  }
}

/// Two-option pill switcher.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.sandDeep,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: C.border),
      ),
      child: Row(
        children: List<Widget>.generate(labels.length, (int index) {
          final bool active = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? C.espresso : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: T.button.copyWith(
                    fontSize: 12.5,
                    color: active ? C.beige : C.roast,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
