import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Explicit team floodlight colors with AA-contrast fallbacks on near-black.
class TeamPalette {
  final Color home;
  final Color away;
  final Color homeInk;
  final Color awayInk;

  const TeamPalette({
    required this.home,
    required this.away,
    required this.homeInk,
    required this.awayInk,
  });

  static const _manifest = <String, Color>{
    'ARG': Color(0xFF74ACDF),
    'BRA': Color(0xFFFEDF00),
    'ENG': Color(0xFFCF081F),
    'ESP': Color(0xFFC60B1E),
    'FRA': Color(0xFF002395),
    'GER': Color(0xFF000000),
    'NED': Color(0xFFFF6600),
    'POR': Color(0xFF006600),
    'URU': Color(0xFF0038A8),
    'USA': Color(0xFF3C3B6E),
    'MEX': Color(0xFF006847),
    'JPN': Color(0xFFBC002D),
    'KOR': Color(0xFFCD2E3A),
    'MAR': Color(0xFFC1272D),
    'SEN': Color(0xFF00853F),
    'CRO': Color(0xFFFF0000),
    'BEL': Color(0xFFFDDA24),
    'ITA': Color(0xFF009246),
  };

  static TeamPalette forFixture(Team home, Team away) {
    final h = _resolve(home);
    final a = _resolve(away);
    return TeamPalette(
      home: h,
      away: a,
      homeInk: _onFlood(h),
      awayInk: _onFlood(a),
    );
  }

  static Color _resolve(Team team) {
    final code = team.code.toUpperCase();
    final named = _manifest[code];
    if (named != null) return named;
    // Deterministic fallback from code hash — saturated but readable.
    final hash = code.codeUnits.fold<int>(0, (a, b) => a * 31 + b);
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.62, 0.42).toColor();
  }

  static Color _onFlood(Color c) {
    final luminance = c.computeLuminance();
    return luminance > 0.45 ? AppColors.ink : AppColors.cream;
  }
}

class HubColors {
  static const stadium = Color(0xFF0B0A08);
  static const stadiumLift = Color(0xFF16130F);
  static const creamSurface = Color(0xFFF5F0E3);
  static const lime = Color(0xFFB8E03A);
  static const violet = Color(0xFF8B5CF6);
  static const stale = Color(0xFFB7AE9C);
}
