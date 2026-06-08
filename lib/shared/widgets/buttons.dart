import 'package:flutter/material.dart';

import '../../core/theme/moona_colors.dart';
import 'moona_icon.dart';

enum MoonaButtonVariant { filled, tonal, text, outlined }

/// Pill button matching the mockup `Button` (filled / tonal / text / outlined,
/// with an optional danger tone and leading icon).
class MoonaButton extends StatelessWidget {
  const MoonaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = MoonaButtonVariant.filled,
    this.icon,
    this.full = false,
    this.danger = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final MoonaButtonVariant variant;
  final String? icon;
  final bool full;
  final bool danger;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg, BoxBorder? border) = switch (variant) {
      MoonaButtonVariant.filled => (
        danger ? c.error : c.primary,
        danger ? c.onErrorContainer : c.onPrimary,
        null,
      ),
      MoonaButtonVariant.tonal => (
        c.primaryContainer,
        c.onPrimaryContainer,
        null,
      ),
      MoonaButtonVariant.text => (
        Colors.transparent,
        danger ? c.error : c.primary,
        null,
      ),
      MoonaButtonVariant.outlined => (
        Colors.transparent,
        danger ? c.error : c.onSurface,
        Border.all(color: danger ? c.error : c.outlineVariant, width: 1.4),
      ),
    };

    final horizontal = variant == MoonaButtonVariant.text ? 14.0 : 22.0;

    return Material(
      color: bg,
      shape: StadiumBorder(
        side: border is Border ? border.top : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: height,
          width: full ? double.infinity : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: Row(
              mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  MoonaIcon(icon!, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
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

/// Circular icon button with an optional notification badge dot.
class MoonaIconButton extends StatelessWidget {
  const MoonaIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 22,
    this.dim = false,
    this.badge = false,
    this.loading = false,
    this.color,
    this.tooltip,
  });

  final String icon;
  final VoidCallback? onPressed;
  final double size;
  final bool dim;
  final bool badge;

  /// Replaces the icon with a small spinner and disables the tap — used to show
  /// background work in place (e.g. the Settings gear while signing in).
  final bool loading;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = color ?? (dim ? c.onSurfaceVariant : c.onSurface);
    final button = SizedBox(
      width: 42,
      height: 42,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(strokeWidth: 2, color: tint),
                )
              else
                MoonaIcon(icon, size: size, color: tint),
              if (badge)
                PositionedDirectional(
                  top: 7,
                  end: 7,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
