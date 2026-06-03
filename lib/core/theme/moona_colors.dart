import 'package:flutter/material.dart';

/// Moona design tokens, ported verbatim from the mockup `store.js` `THEME`.
///
/// These are the warm, green Material-3 surface ladder and accent colors the
/// prototype uses. They are exposed as a [ThemeExtension] so widgets read exact
/// token values (e.g. the surface-container steps and the field background)
/// rather than approximating them from the generated [ColorScheme].
@immutable
class MoonaColors extends ThemeExtension<MoonaColors> {
  const MoonaColors({
    required this.surface,
    required this.surfaceLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.outline,
    required this.outlineVariant,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.scrim,
    required this.shadow,
    required this.field,
  });

  final Color surface;
  final Color surfaceLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color outline;
  final Color outlineVariant;
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color scrim;
  final Color shadow;
  final Color field;

  static const MoonaColors light = MoonaColors(
    surface: Color(0xFFFFFBF6),
    surfaceLow: Color(0xFFFBF5EE),
    surfaceContainer: Color(0xFFF4EFE7),
    surfaceContainerHigh: Color(0xFFEEE8DE),
    surfaceContainerHighest: Color(0xFFE8E2D8),
    onSurface: Color(0xFF1D1B18),
    onSurfaceVariant: Color(0xFF524D45),
    primary: Color(0xFF1F8A5B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFB7F2CE),
    onPrimaryContainer: Color(0xFF00210F),
    outline: Color(0xFF857F75),
    outlineVariant: Color(0xFFD6CFC3),
    error: Color(0xFFBA1A1A),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    scrim: Color(0x6B282218),
    shadow: Color(0x293C321E),
    field: Color(0xFFFFFFFF),
  );

  static const MoonaColors dark = MoonaColors(
    surface: Color(0xFF14130F),
    surfaceLow: Color(0xFF1C1B16),
    surfaceContainer: Color(0xFF211F1A),
    surfaceContainerHigh: Color(0xFF2B2924),
    surfaceContainerHighest: Color(0xFF36332E),
    onSurface: Color(0xFFECE7DD),
    onSurfaceVariant: Color(0xFFCFC8BC),
    primary: Color(0xFF6EDDA1),
    onPrimary: Color(0xFF003820),
    primaryContainer: Color(0xFF00522F),
    onPrimaryContainer: Color(0xFF8BFABB),
    outline: Color(0xFF9A9286),
    outlineVariant: Color(0xFF4C4740),
    error: Color(0xFFFFB4AB),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    scrim: Color(0x8C000000),
    shadow: Color(0x80000000),
    field: Color(0xFF211F1A),
  );

  @override
  MoonaColors copyWith({
    Color? surface,
    Color? surfaceLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? outline,
    Color? outlineVariant,
    Color? error,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? scrim,
    Color? shadow,
    Color? field,
  }) {
    return MoonaColors(
      surface: surface ?? this.surface,
      surfaceLow: surfaceLow ?? this.surfaceLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      field: field ?? this.field,
    );
  }

  @override
  MoonaColors lerp(ThemeExtension<MoonaColors>? other, double t) {
    if (other is! MoonaColors) return this;
    return MoonaColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLow: Color.lerp(surfaceLow, other.surfaceLow, t)!,
      surfaceContainer: Color.lerp(
        surfaceContainer,
        other.surfaceContainer,
        t,
      )!,
      surfaceContainerHigh: Color.lerp(
        surfaceContainerHigh,
        other.surfaceContainerHigh,
        t,
      )!,
      surfaceContainerHighest: Color.lerp(
        surfaceContainerHighest,
        other.surfaceContainerHighest,
        t,
      )!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant: Color.lerp(
        onSurfaceVariant,
        other.onSurfaceVariant,
        t,
      )!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer: Color.lerp(
        primaryContainer,
        other.primaryContainer,
        t,
      )!,
      onPrimaryContainer: Color.lerp(
        onPrimaryContainer,
        other.onPrimaryContainer,
        t,
      )!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(
        onErrorContainer,
        other.onErrorContainer,
        t,
      )!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      field: Color.lerp(field, other.field, t)!,
    );
  }
}

/// Convenience access to [MoonaColors] from a [BuildContext].
extension MoonaColorsX on BuildContext {
  MoonaColors get c => Theme.of(this).extension<MoonaColors>()!;
}
