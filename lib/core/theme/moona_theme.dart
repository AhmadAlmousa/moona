import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'moona_colors.dart';

/// Builds the Moona [ThemeData] for a given [brightness] and language.
///
/// The mockup pairs **Nunito** (rounded Latin) with **Cairo** (Arabic). The
/// active language picks the primary family and the other becomes the fallback,
/// so mixed-script content (e.g. an Arabic brand inside an English UI) still
/// renders correctly.
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

  final primaryFamily =
      (arabic ? GoogleFonts.cairo() : GoogleFonts.nunito()).fontFamily;
  final fallbackFamily =
      (arabic ? GoogleFonts.nunito() : GoogleFonts.cairo()).fontFamily;

  final baseText = arabic
      ? GoogleFonts.cairoTextTheme()
      : GoogleFonts.nunitoTextTheme();
  final textTheme = baseText.apply(
    bodyColor: tokens.onSurface,
    displayColor: tokens.onSurface,
    fontFamilyFallback: [fallbackFamily!],
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surface,
    canvasColor: tokens.surface,
    fontFamily: primaryFamily,
    fontFamilyFallback: [fallbackFamily],
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    extensions: [tokens],
  );
}
