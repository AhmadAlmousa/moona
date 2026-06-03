import 'package:flutter/material.dart';

import '../../core/theme/moona_colors.dart';

/// Toggle switch matching the mockup `Switch` (track + growing thumb).
class MoonaSwitch extends StatelessWidget {
  const MoonaSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 52,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: value ? c.primary : c.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
          border: value ? null : Border.all(color: c.outline, width: 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: value ? 22 : 16,
            height: value ? 22 : 16,
            decoration: BoxDecoration(
              color: value ? c.onPrimary : c.outline,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Round avatar showing the first letter of [name].
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.tint = false,
    this.size = 44,
  });

  final String name;
  final bool tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final letter = (name.isEmpty ? '?' : name.characters.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint ? c.primaryContainer : c.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: tint ? c.onPrimaryContainer : c.onPrimary,
          fontSize: size * 0.41,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Uppercase section header used in settings.
class MoonaSection extends StatelessWidget {
  const MoonaSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 9),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: c.primary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// Tappable surface-container row used in settings/sharing.
class MoonaRow extends StatelessWidget {
  const MoonaRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
