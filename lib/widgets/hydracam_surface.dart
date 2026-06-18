import "package:flutter/material.dart";

import "../app_theme.dart";

enum HydraCamSurfaceTone {
  defaultTone,
  muted,
  dark,
  danger,
}

enum HydraCamStatusTone {
  neutral,
  active,
  warning,
  danger,
  recording,
}

enum HydraCamButtonVariant {
  primary,
  neutral,
  danger,
}

class HydraCamSurface extends StatelessWidget {
  const HydraCamSurface({
    super.key,
    required this.child,
    this.tone = HydraCamSurfaceTone.defaultTone,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  final Widget child;
  final HydraCamSurfaceTone tone;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  Color get _backgroundColor {
    return switch (tone) {
      HydraCamSurfaceTone.defaultTone => AppTheme.surface,
      HydraCamSurfaceTone.muted => AppTheme.surfaceMuted,
      HydraCamSurfaceTone.dark => AppTheme.appChrome,
      HydraCamSurfaceTone.danger => AppTheme.dangerSurface,
    };
  }

  Color get _borderColor {
    return switch (tone) {
      HydraCamSurfaceTone.danger => AppTheme.danger,
      HydraCamSurfaceTone.dark => AppTheme.borderStrong,
      _ => AppTheme.border,
    };
  }

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: _backgroundColor,
        border: Border.all(color: _borderColor),
        borderRadius: AppTheme.smallRadius,
      ),
      child: Padding(
        padding: padding,
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: tone == HydraCamSurfaceTone.dark
                  ? AppTheme.inverseText
                  : AppTheme.textPrimary,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (margin == null) {
      return content;
    }

    return Padding(
      padding: margin!,
      child: content,
    );
  }
}

class HydraCamToolbar extends StatelessWidget {
  const HydraCamToolbar({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return HydraCamSurface(
      tone: HydraCamSurfaceTone.muted,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: children,
      ),
    );
  }
}

class HydraCamButton extends StatelessWidget {
  const HydraCamButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.variant = HydraCamButtonVariant.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final HydraCamButtonVariant variant;

  ButtonStyle _style(BuildContext context) {
    return switch (variant) {
      HydraCamButtonVariant.primary => AppTheme.primaryButtonStyle(),
      HydraCamButtonVariant.danger => AppTheme.dangerButtonStyle(),
      HydraCamButtonVariant.neutral => ElevatedButton.styleFrom(
          backgroundColor: AppTheme.surface,
          foregroundColor: AppTheme.textPrimary,
          disabledBackgroundColor: AppTheme.disabledSurface,
          disabledForegroundColor: AppTheme.textSecondary,
          side: const BorderSide(color: AppTheme.border),
          shape: const RoundedRectangleBorder(
            borderRadius: AppTheme.smallRadius,
          ),
          minimumSize: const Size(0, 44),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: _style(context),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class HydraCamBadge extends StatelessWidget {
  const HydraCamBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = HydraCamStatusTone.neutral,
  });

  final String label;
  final IconData? icon;
  final HydraCamStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class HydraCamStatusChip extends StatelessWidget {
  const HydraCamStatusChip({
    super.key,
    required this.status,
    required this.label,
    this.icon,
  });

  final HydraCamStatusTone status;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(status);
    return Chip(
      avatar:
          icon == null ? null : Icon(icon, size: 16, color: colors.foreground),
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w700,
          ),
      backgroundColor: colors.background,
      side: BorderSide(color: colors.border),
      shape: const RoundedRectangleBorder(borderRadius: AppTheme.smallRadius),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusColors {
  const _StatusColors({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

_StatusColors _statusColors(HydraCamStatusTone tone) {
  return switch (tone) {
    HydraCamStatusTone.neutral => const _StatusColors(
        foreground: AppTheme.textSecondary,
        background: AppTheme.surfaceMuted,
        border: AppTheme.border,
      ),
    HydraCamStatusTone.active => const _StatusColors(
        foreground: AppTheme.textPrimary,
        background: AppTheme.accent,
        border: AppTheme.accent,
      ),
    HydraCamStatusTone.warning => const _StatusColors(
        foreground: AppTheme.textPrimary,
        background: AppTheme.accentSurface,
        border: AppTheme.accent,
      ),
    HydraCamStatusTone.danger => const _StatusColors(
        foreground: AppTheme.danger,
        background: AppTheme.dangerSurface,
        border: AppTheme.danger,
      ),
    HydraCamStatusTone.recording => const _StatusColors(
        foreground: AppTheme.inverseText,
        background: AppTheme.danger,
        border: AppTheme.danger,
      ),
  };
}
