import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'i18n.dart';

export 'i18n.dart';

/// Colours taken from the CVSAFE mobile mock-ups, with a light variant.
///
/// Neutral colours (and the accents that need more contrast on white) follow
/// [UiPrefs.dark]; the brand orange and alarm reds are the same in both themes.
class C {
  static bool get _d => UiPrefs.instance.dark;

  static Color get bg => _d ? const Color(0xFF0D1626) : const Color(0xFFF3F5F9);
  static Color get panel => _d ? const Color(0xFF15213A) : const Color(0xFFFFFFFF);
  static Color get panel2 => _d ? const Color(0xFF1B2944) : const Color(0xFFEDF1F7);
  static Color get border => _d ? const Color(0xFF26364F) : const Color(0xFFD6DDE8);
  static Color get text => _d ? const Color(0xFFE5E7EB) : const Color(0xFF0F172A);
  static Color get muted => _d ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  static Color get dim => _d ? const Color(0xFF64748B) : const Color(0xFF7C8AA0);
  static Color get green => _d ? const Color(0xFF34D399) : const Color(0xFF059669);
  static Color get pink => _d ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
  static Color get blue => _d ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
  static Color get yellow => _d ? const Color(0xFFFBBF24) : const Color(0xFFB45309);

  static const orange = Color(0xFFF97316);
  static const red = Color(0xFFEF4444);
  static const greenDark = Color(0xFF065F46);
  static const redDark = Color(0xFF7F1D1D);

  /// Background for alert snack bars, which use white text in both themes.
  static const snack = Color(0xFF1B2944);
}

Color alpha(Color c, double opacity) => c.withAlpha((opacity * 255).round().clamp(0, 255));

TextStyle mono({double size = 13, Color? color, FontWeight weight = FontWeight.w500, double? spacing}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color ?? C.text, fontWeight: weight, letterSpacing: spacing);

TextStyle sans({double size = 14, Color? color, FontWeight weight = FontWeight.w400, double? height}) =>
    GoogleFonts.inter(fontSize: size, color: color ?? C.text, fontWeight: weight, height: height);

ThemeData buildTheme() {
  final dark = UiPrefs.instance.dark;
  final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.panel,
    dividerColor: C.border,
    colorScheme: base.colorScheme.copyWith(
      primary: C.orange,
      onPrimary: Colors.white,
      secondary: C.green,
      surface: C.panel,
      onSurface: C.text,
      error: C.red,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.text),
    iconTheme: IconThemeData(color: C.muted),
    snackBarTheme: SnackBarThemeData(backgroundColor: C.panel2, behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.orange),
  );
}

Color severityColor(String s) {
  switch (s) {
    case 'critical':
      return C.red;
    case 'high':
      return C.orange;
    case 'moderate':
      return C.yellow;
    default:
      return C.blue;
  }
}
