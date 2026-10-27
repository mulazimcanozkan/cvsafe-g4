import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours taken from the CVSAFE mobile mock-ups.
class C {
  static const bg = Color(0xFF0D1626);
  static const panel = Color(0xFF15213A);
  static const panel2 = Color(0xFF1B2944);
  static const border = Color(0xFF26364F);
  static const orange = Color(0xFFF97316);
  static const green = Color(0xFF34D399);
  static const greenDark = Color(0xFF065F46);
  static const red = Color(0xFFEF4444);
  static const redDark = Color(0xFF7F1D1D);
  static const pink = Color(0xFFFCA5A5);
  static const blue = Color(0xFF60A5FA);
  static const yellow = Color(0xFFFBBF24);
  static const text = Color(0xFFE5E7EB);
  static const muted = Color(0xFF94A3B8);
  static const dim = Color(0xFF64748B);
}

Color alpha(Color c, double opacity) => c.withAlpha((opacity * 255).round().clamp(0, 255));

TextStyle mono({double size = 13, Color color = C.text, FontWeight weight = FontWeight.w500, double? spacing}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing);

TextStyle sans({double size = 14, Color color = C.text, FontWeight weight = FontWeight.w400, double? height}) =>
    GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight, height: height);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(primary: C.orange, secondary: C.green, surface: C.panel, error: C.red),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.text),
    snackBarTheme: const SnackBarThemeData(backgroundColor: C.panel2, behavior: SnackBarBehavior.floating),
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
