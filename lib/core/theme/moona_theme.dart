import 'package:flutter/material.dart';

import 'moona_colors.dart';

/// Builds the Moona [ThemeData] for a given [brightness] and language.
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
    fontFamily: _fontFamily,
    splashFactory: InkSparkle.splashFactory,
    extensions: [tokens],
  );
}

const _fontFamily = 'Roboto';
