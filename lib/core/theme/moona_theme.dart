import 'package:flutter/material.dart';

import 'moona_colors.dart';

/// Builds the Moona [ThemeData] for a given [brightness] and language.
///
/// The mockup pairs **Nunito** (rounded Latin) with **Cairo** (Arabic). The
/// active language picks the primary family and the other becomes the fallback,
/// so mixed-script content (e.g. an Arabic brand inside an English UI) still
/// renders correctly. Both are bundled variable fonts (see `pubspec.yaml`).
ThemeData buildMoonaTheme({
  required Brightness brightness,
  required bool arabic,
}) {
  final tokens = brightness == Brightness.dark
      ? MoonaColors.dark
      : MoonaColors.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F8A5B),
        brightness: brightness,
      ).copyWith(
        primary: tokens.primary,
        onPrimary: tokens.onPrimary,
        primaryContainer: tokens.primaryContainer,
        onPrimaryContainer: tokens.onPrimaryContainer,
        surface: tokens.surface,
        onSurface: tokens.onSurface,
        onSurfaceVariant: tokens.onSurfaceVariant,
        error: tokens.error,
        errorContainer: tokens.errorContainer,
        onErrorContainer: tokens.onErrorContainer,
        outline: tokens.outline,
        outlineVariant: tokens.outlineVariant,
        scrim: tokens.scrim,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surface,
    canvasColor: tokens.surface,
    fontFamily: arabic ? _cairo : _nunito,
    fontFamilyFallback: [arabic ? _nunito : _cairo],
    splashFactory: InkSparkle.splashFactory,
    extensions: [tokens],
  );
}

const _cairo = 'Cairo';
const _nunito = 'Nunito';
