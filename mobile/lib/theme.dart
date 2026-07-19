import 'package:flutter/material.dart';

/// "Terrace" design language — warm matchday paper, bold display type,
/// ticket-stub scoreboards, vivid orange accent.
class AppColors {
  static const paper = Color(0xFFE9E4D6); // page background (warm newsprint)
  static const paperDeep = Color(0xFFE2DBC8);
  static const card = Color(0xFFFAF6EC); // cream card
  static const cardAlt = Color(0xFFF2ECDD);
  static const ink = Color(0xFF17130E); // near-black ticket panel + text
  static const inkSoft = Color(0xFF2C261D);
  static const cream = Color(0xFFF5F0E3); // text on ink
  static const orange = Color(0xFFE9531E); // primary accent / CTA
  static const orangeBright = Color(0xFFF26A21); // scores
  static const mut = Color(0xFF8B8273); // secondary on paper
  static const mutInk = Color(0xFFB7AE9C); // secondary on ink
  static const line = Color(0xFFDCD4C1); // card border on paper
  static const lineInk = Color(0xFF342D22);
  static const gold = Color(0xFFE0A33C);
}

/// Product-wide adaptive stadium tokens. Legacy paper tokens remain for dense
/// reading sheets while primary destinations use this darker system.
class StadiumColors {
  static const canvas = Color(0xFF070A0F);
  static const canvasRaised = Color(0xFF0D121A);
  static const navigation = Color(0xFF090D13);
  static const panel = Color(0xFF121924);
  static const panelRaised = Color(0xFF182231);
  static const panelWarm = Color(0xFF211B17);
  static const hairline = Color(0xFF263244);
  static const text = Color(0xFFF7F1E5);
  static const textSoft = Color(0xFFD3CCBF);
  static const muted = Color(0xFF8995A5);
  static const orange = Color(0xFFF45B24);
  static const live = Color(0xFFFF4D37);
  static const mint = Color(0xFF55E3A4);
  static const lime = Color(0xFFB8FF36);
  static const violet = Color(0xFF9B6BFF);
  static const gold = Color(0xFFF5C451);
  static const amber = Color(0xFFFFC857);
}

const kDisplay = 'Anton';
const kBody = 'Archivo';

ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: StadiumColors.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: StadiumColors.orange,
      secondary: StadiumColors.violet,
      surface: StadiumColors.panel,
      onSurface: StadiumColors.text,
      brightness: Brightness.dark,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: StadiumColors.text,
      displayColor: StadiumColors.text,
      fontFamily: kBody,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StadiumColors.canvas,
      foregroundColor: StadiumColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dividerColor: StadiumColors.hairline,
    dialogTheme: const DialogThemeData(
      backgroundColor: StadiumColors.panel,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: StadiumColors.canvasRaised,
      surfaceTintColor: Colors.transparent,
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

BoxDecoration stadiumPanel({
  Color? color,
  Color? border,
  double radius = 20,
  List<BoxShadow>? shadow,
}) => BoxDecoration(
  color: color ?? StadiumColors.panel,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: border ?? StadiumColors.hairline),
  boxShadow: shadow,
);

BoxDecoration stadiumGradientPanel({
  required Color accent,
  double radius = 24,
}) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(
        accent.withValues(alpha: .24),
        StadiumColors.panelRaised,
      ),
      StadiumColors.panel,
      StadiumColors.canvasRaised,
    ],
    stops: const [0, .52, 1],
  ),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: accent.withValues(alpha: .42)),
  boxShadow: [
    BoxShadow(
      color: accent.withValues(alpha: .11),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
  ],
);

/// Heavy condensed display text (Anton).
TextStyle display(
  double size, {
  Color color = AppColors.ink,
  double spacing = 0,
}) => TextStyle(
  fontFamily: kDisplay,
  fontSize: size,
  color: color,
  height: 1.0,
  letterSpacing: spacing,
);

/// Small uppercase label (Archivo, tracked).
TextStyle label({
  Color color = AppColors.mut,
  double size = 11,
  FontWeight weight = FontWeight.w700,
}) => TextStyle(
  fontFamily: kBody,
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: 1.4,
);

TextStyle body({
  Color color = AppColors.ink,
  double size = 14,
  FontWeight weight = FontWeight.w500,
}) => TextStyle(
  fontFamily: kBody,
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.35,
);

/// Cream card with warm border + soft shadow.
BoxDecoration cardBox({Color? color, Color? border, double radius = 18}) =>
    BoxDecoration(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? AppColors.line, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    );

/// Team identity colour for the badge circles (keyed by 3-letter code).
const _teamColors = <String, int>{
  'ARG': 0xFF5BA3D0,
  'BRA': 0xFF2BB673,
  'FRA': 0xFF1B3A8C,
  'ESP': 0xFFD8392B,
  'GER': 0xFF1A1A1A,
  'ENG': 0xFFD8392B,
  'POR': 0xFF1F7A3D,
  'NED': 0xFFEB6A1E,
  'BEL': 0xFFD8392B,
  'CRO': 0xFFD8392B,
  'URU': 0xFF5BA3D0,
  'MEX': 0xFF1F7A3D,
  'USA': 0xFF1B3A8C,
  'JPN': 0xFFD8392B,
  'MAR': 0xFFB4232A,
  'SEN': 0xFF1F7A3D,
  'DEN': 0xFFD8392B,
  'SUI': 0xFFD8392B,
  'SRB': 0xFF8C2832,
  'POL': 0xFFD8392B,
  'KOR': 0xFF1B3A8C,
  'CAN': 0xFFD8392B,
  'COL': 0xFFF2C300,
  'NGA': 0xFF1F7A3D,
  'ECU': 0xFFF2C300,
  'GHA': 0xFF1A1A1A,
  'CMR': 0xFF1F7A3D,
  'AUS': 0xFFC2A000,
};

const _palette = [
  0xFFD8392B,
  0xFF1B3A8C,
  0xFF1F7A3D,
  0xFFEB6A1E,
  0xFF6A3FA0,
  0xFF0E8C8C,
];

Color teamColor(String code) {
  final hit = _teamColors[code.toUpperCase()];
  if (hit != null) return Color(hit);
  var h = 0;
  for (final c in code.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return Color(_palette[h % _palette.length]);
}
