---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/oddjobz_visuals.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.462636+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/oddjobz_visuals.dart

```dart
import 'package:flutter/material.dart';

/// OddJobz field-notebook visual language, adapted from the archived helm
/// wireframes in Todd's oddjobz.zip.
///
/// Keep this cartridge-scoped. The Semantos shell and other cartridges should
/// not inherit this paper/ink treatment.
abstract final class OddjobzVisuals {
  static const paper = Color(0xFFF6F1E7);
  static const paperWarm = Color(0xFFFBF7EC);
  static const paperShadow = Color(0xFFE9E0CD);
  static const ink = Color(0xFF2A2722);
  static const inkSoft = Color(0xFF6B6558);
  static const inkFaint = Color(0xFFA8A193);
  static const rule = Color(0xFFC9C0AD);
  static const activation = Color(0xFFC46A3A);
  static const activationSoft = Color(0xFFE6C9B3);
  static const hold = Color(0xFF5A8A6F);
  static const linear = Color(0xFFB8442E);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: activation,
      brightness: Brightness.light,
      surface: paper,
      primary: activation,
      secondary: hold,
      error: linear,
    );
    return base.copyWith(
      colorScheme: scheme.copyWith(
        surface: paper,
        surfaceContainerLowest: paperWarm,
        surfaceContainerLow: paperWarm,
        surfaceContainer: paper,
        surfaceContainerHigh: paperShadow,
        surfaceContainerHighest: activationSoft.withOpacity(0.38),
        outline: rule,
        outlineVariant: rule.withOpacity(0.72),
        onSurface: ink,
        onSurfaceVariant: inkSoft,
      ),
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paperShadow.withOpacity(0.62),
        indicatorColor: activationSoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            letterSpacing: 1.0,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? ink : inkSoft,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? activation : inkSoft,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paperWarm,
        selectedColor: activationSoft,
        side: const BorderSide(color: rule),
        labelStyle: const TextStyle(
          color: inkSoft,
          fontFamily: 'monospace',
          fontSize: 11,
          letterSpacing: 0.7,
        ),
      ),
      dividerTheme: const DividerThemeData(color: rule, thickness: 1, space: 1),
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            labelSmall: base.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: inkSoft,
              letterSpacing: 1.2,
            ),
          ),
    );
  }
}

class OddjobzPaper extends StatelessWidget {
  const OddjobzPaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: OddjobzVisuals.theme(context), child: child);
  }
}

class OddjobzSectionLabel extends StatelessWidget {
  const OddjobzSectionLabel({
    super.key,
    required this.label,
    this.count,
    this.icon,
  });

  final String label;
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: const BoxDecoration(
        color: OddjobzVisuals.paperShadow,
        border: Border(
          top: BorderSide(color: OddjobzVisuals.rule),
          bottom: BorderSide(color: OddjobzVisuals.rule),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: OddjobzVisuals.activation),
            const SizedBox(width: 8),
          ],
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: OddjobzVisuals.inkSoft,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            OddjobzCountBadge(count: count!),
          ],
        ],
      ),
    );
  }
}

class OddjobzCountBadge extends StatelessWidget {
  const OddjobzCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: OddjobzVisuals.activationSoft.withOpacity(0.72),
        border: Border.all(color: OddjobzVisuals.rule),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: OddjobzVisuals.ink,
        ),
      ),
    );
  }
}

class OddjobzCard extends StatelessWidget {
  const OddjobzCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: padding,
      decoration: BoxDecoration(
        color: OddjobzVisuals.paperWarm,
        border: Border.all(
          color: OddjobzVisuals.ink.withOpacity(0.72),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: OddjobzVisuals.paperShadow, offset: Offset(2, 3)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: card,
    );
  }
}

class OddjobzStatePill extends StatelessWidget {
  const OddjobzStatePill({super.key, required this.label, this.done = false});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? OddjobzVisuals.hold : OddjobzVisuals.activation;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

```
