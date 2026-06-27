import 'package:flutter/material.dart';

/// Design tokens mirrored from the web app for a consistent brand.
class AppColors {
  static const pitch950 = Color(0xFF070B14);
  static const pitch900 = Color(0xFF0B1220);
  static const pitch850 = Color(0xFF0F1828);
  static const pitch800 = Color(0xFF141F33);
  static const pitch700 = Color(0xFF1D2C45);
  static const line = Color(0xFF243650);

  static const lime = Color(0xFFC7F24D);
  static const limeSoft = Color(0xFFD8FF6B);
  static const home = Color(0xFF4AA3FF);
  static const away = Color(0xFFFF6B6B);
  static const gold = Color(0xFFFFD24A);
  static const mut = Color(0xFF8AA0BD);
  static const text = Color(0xFFEAF1FB);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.pitch950,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.lime,
      secondary: AppColors.home,
      surface: AppColors.pitch850,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamily: 'SF Pro Text',
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

/// Reusable card decoration.
BoxDecoration cardDecoration({Color? borderColor, Color? leftAccent}) {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xE6141F33), Color(0xE60F1828)],
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border(
      top: BorderSide(color: borderColor ?? AppColors.line),
      right: BorderSide(color: borderColor ?? AppColors.line),
      bottom: BorderSide(color: borderColor ?? AppColors.line),
      left: leftAccent != null
          ? BorderSide(color: leftAccent, width: 4)
          : BorderSide(color: borderColor ?? AppColors.line),
    ),
  );
}

BoxDecoration chipDecoration({Color? border}) => BoxDecoration(
      color: const Color(0xB30F1828),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border ?? AppColors.line),
    );
