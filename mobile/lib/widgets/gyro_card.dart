import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/player_portraits.dart';
import '../theme.dart';

const _teamFlags = <String, String>{
  'ARG': '🇦🇷',
  'AUS': '🇦🇺',
  'BEL': '🇧🇪',
  'BRA': '🇧🇷',
  'CAN': '🇨🇦',
  'COL': '🇨🇴',
  'CRO': '🇭🇷',
  'DEN': '🇩🇰',
  'ECU': '🇪🇨',
  'EGY': '🇪🇬',
  'ENG': '🏴',
  'FRA': '🇫🇷',
  'GER': '🇩🇪',
  'GHA': '🇬🇭',
  'IRN': '🇮🇷',
  'ITA': '🇮🇹',
  'JPN': '🇯🇵',
  'KOR': '🇰🇷',
  'MEX': '🇲🇽',
  'MAR': '🇲🇦',
  'NED': '🇳🇱',
  'NGA': '🇳🇬',
  'NOR': '🇳🇴',
  'POL': '🇵🇱',
  'POR': '🇵🇹',
  'KSA': '🇸🇦',
  'SEN': '🇸🇳',
  'SRB': '🇷🇸',
  'ESP': '🇪🇸',
  'SUI': '🇨🇭',
  'SWE': '🇸🇪',
  'URU': '🇺🇾',
  'USA': '🇺🇸',
};

enum CardMotionAvailability { unknown, available, unavailable }

enum CardInteractionMode { sensor, drag, reducedMotion }

enum CardFrameShape { relic, stadiumCrown }

enum RarityMaterial { matte, gloss, holographic, prismatic, gold }

enum CollectibleLayerProfile { moment, player, skill }

@immutable
class MotionVectorSample {
  final double x, y, z;
  final int timestampMicros;

  const MotionVectorSample({
    required this.x,
    required this.y,
    required this.z,
    required this.timestampMicros,
  });
}

abstract interface class CardMotionSource {
  Stream<MotionVectorSample> get acceleration;
  Stream<MotionVectorSample> get rotation;
}

class SensorCardMotionSource implements CardMotionSource {
  const SensorCardMotionSource();

  @override
  Stream<MotionVectorSample> get acceleration =>
      accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).map(
        (e) => MotionVectorSample(
          x: e.x,
          y: e.y,
          z: e.z,
          timestampMicros: DateTime.now().microsecondsSinceEpoch,
        ),
      );

  @override
  Stream<MotionVectorSample> get rotation =>
      gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval).map(
        (e) => MotionVectorSample(
          x: e.x,
          y: e.y,
          z: e.z,
          timestampMicros: DateTime.now().microsecondsSinceEpoch,
        ),
      );
}

@immutable
class CardMotionSnapshot {
  final double x, y;
  final CardMotionAvailability availability;
  final CardInteractionMode mode;
  final bool calibrated;

  const CardMotionSnapshot({
    this.x = 0,
    this.y = 0,
    this.availability = CardMotionAvailability.unknown,
    this.mode = CardInteractionMode.sensor,
    this.calibrated = false,
  });

  CardMotionSnapshot copyWith({
    double? x,
    double? y,
    CardMotionAvailability? availability,
    CardInteractionMode? mode,
    bool? calibrated,
  }) => CardMotionSnapshot(
    x: x ?? this.x,
    y: y ?? this.y,
    availability: availability ?? this.availability,
    mode: mode ?? this.mode,
    calibrated: calibrated ?? this.calibrated,
  );
}

/// One calibrated, fused stream shared by an Album/detail scene.
class CardMotionController extends ChangeNotifier {
  final CardMotionSource source;
  StreamSubscription<MotionVectorSample>? _accel;
  StreamSubscription<MotionVectorSample>? _gyro;
  CardMotionSnapshot _snapshot = const CardMotionSnapshot();
  double _pitch = 0, _roll = 0, _neutralPitch = 0, _neutralRoll = 0;
  double _dragX = 0, _dragY = 0;
  int? _lastGyroMicros;
  Timer? _spring;
  bool _started = false;

  CardMotionController({CardMotionSource? source})
    : source = source ?? const SensorCardMotionSource();

  CardMotionSnapshot get snapshot => _snapshot;
  double get x => (_snapshot.x + _dragX).clamp(-1.0, 1.0);
  double get y => (_snapshot.y + _dragY).clamp(-1.0, 1.0);
  bool get hasMoved => x.abs() > 0.06 || y.abs() > 0.06;

  void start() {
    if (_started) return;
    _started = true;
    try {
      _accel = source.acceleration.listen(_onAcceleration, onError: _onError);
      _gyro = source.rotation.listen(_onRotation, onError: _onError);
    } catch (error) {
      _onError(error);
    }
  }

  void _onAcceleration(MotionVectorSample sample) {
    final pitch = math.atan2(
      sample.x,
      math.sqrt(sample.y * sample.y + sample.z * sample.z),
    );
    final roll = math.atan2(sample.z, sample.y);
    if (!_snapshot.calibrated) {
      _neutralPitch = pitch;
      _neutralRoll = roll;
      _pitch = pitch;
      _roll = roll;
      _snapshot = _snapshot.copyWith(
        calibrated: true,
        availability: CardMotionAvailability.available,
      );
      notifyListeners();
      return;
    }

    // Gravity corrects gyro drift while preserving the fluid response.
    _pitch = _pitch * 0.88 + pitch * 0.12;
    _roll = _roll * 0.88 + roll * 0.12;
    _publishOrientation();
  }

  void _onRotation(MotionVectorSample sample) {
    final previous = _lastGyroMicros;
    _lastGyroMicros = sample.timestampMicros;
    if (previous == null || !_snapshot.calibrated) return;
    final dt = ((sample.timestampMicros - previous) / 1000000.0).clamp(
      0.0,
      0.05,
    );
    _pitch += sample.y * dt;
    _roll += sample.x * dt;
    _publishOrientation();
  }

  void _publishOrientation() {
    const travel = 0.48; // about 27.5 degrees from the calibrated pose.
    var nx = ((_pitch - _neutralPitch) / travel).clamp(-1.0, 1.0);
    var ny = ((_roll - _neutralRoll) / travel).clamp(-1.0, 1.0);
    if (nx.abs() < 0.025) nx = 0;
    if (ny.abs() < 0.025) ny = 0;
    _snapshot = _snapshot.copyWith(
      x: _snapshot.x * 0.68 + nx * 0.32,
      y: _snapshot.y * 0.68 + ny * 0.32,
      availability: CardMotionAvailability.available,
      mode: CardInteractionMode.sensor,
    );
    notifyListeners();
  }

  void _onError(Object _) {
    _snapshot = _snapshot.copyWith(
      availability: CardMotionAvailability.unavailable,
      mode: CardInteractionMode.drag,
    );
    notifyListeners();
  }

  void drag(Offset delta) {
    _spring?.cancel();
    _dragX = (_dragX + delta.dx * 0.009).clamp(-1.0, 1.0);
    _dragY = (_dragY + delta.dy * 0.009).clamp(-1.0, 1.0);
    _snapshot = _snapshot.copyWith(mode: CardInteractionMode.drag);
    notifyListeners();
  }

  void resetDrag() {
    _spring?.cancel();
    _spring = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _dragX *= 0.76;
      _dragY *= 0.76;
      if (_dragX.abs() < 0.003 && _dragY.abs() < 0.003) {
        _dragX = 0;
        _dragY = 0;
        timer.cancel();
        _snapshot = _snapshot.copyWith(mode: CardInteractionMode.sensor);
      }
      notifyListeners();
    });
  }

  void pause() {
    _accel?.cancel();
    _gyro?.cancel();
    _accel = null;
    _gyro = null;
    _started = false;
    _lastGyroMicros = null;
  }

  void resume() => start();

  @override
  void dispose() {
    _spring?.cancel();
    _accel?.cancel();
    _gyro?.cancel();
    super.dispose();
  }
}

/// Exposes tilt + parallax scale to card faces without prop-drilling.
class CardMotionScope extends InheritedNotifier<CardMotionController> {
  final CardMotionController motion;
  final double intensity;
  final bool reduceParallax;
  final int seed;
  final int rarity;
  final Color foilAccent;

  const CardMotionScope({
    super.key,
    required this.motion,
    required this.intensity,
    required this.reduceParallax,
    required this.seed,
    required this.rarity,
    required this.foilAccent,
    required super.child,
  }) : super(notifier: motion);

  static CardMotionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardMotionScope>();

  double get parallaxScale => reduceParallax ? 0.0 : intensity;

  double get x => motion.x * intensity;
  double get y => motion.y * intensity;

  @override
  bool updateShouldNotify(CardMotionScope oldWidget) =>
      intensity != oldWidget.intensity ||
      reduceParallax != oldWidget.reduceParallax ||
      seed != oldWidget.seed ||
      rarity != oldWidget.rarity ||
      foilAccent != oldWidget.foilAccent ||
      super.updateShouldNotify(oldWidget);
}

/// Stable hash for procedural uniqueness (foil phase, motif placement).
int cardSeed(String input) {
  var h = 2166136261;
  for (final c in input.codeUnits) {
    h ^= c;
    h = (h * 16777619) & 0x7fffffff;
  }
  return h;
}

/// Translates a child by motion × depth for Matchics-style layered parallax.
class ParallaxLayer extends StatelessWidget {
  final double depth;
  final String? debugLabel;
  final Widget child;

  const ParallaxLayer({
    super.key,
    required this.depth,
    this.debugLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scope = CardMotionScope.maybeOf(context);
    if (scope == null || scope.parallaxScale == 0) return child;
    final k = scope.parallaxScale;
    return Transform.translate(
      key: debugLabel == null ? null : ValueKey('parallax-$debugLabel'),
      offset: Offset(scope.motion.x * depth * k, scope.motion.y * depth * k),
      child: child,
    );
  }
}

/// Rarity-gated holographic foil that tracks device tilt.
class CardFoilOverlay extends StatelessWidget {
  const CardFoilOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = CardMotionScope.maybeOf(context);
    final mx = scope?.motion.x ?? 0.0;
    final my = scope?.motion.y ?? 0.0;
    final rarity = scope?.rarity ?? 1;
    final accent = scope?.foilAccent ?? const Color(0xFF9B6BFF);
    final seed = scope?.seed ?? 0;
    final phase = ((seed % 1000) / 1000.0) * 0.6;

    final shift = mx + phase;
    final begin = Alignment(-1.2 + (shift + 1) * 0.9, -1.1 + my * 0.35);
    final end = Alignment(1.2 + (shift + 1) * 0.55, 1.1 + my * 0.2);

    final List<Color> colors;
    final List<double> stops;
    switch (rarity.clamp(1, 5)) {
      case 5:
        colors = [
          Colors.transparent,
          Color.lerp(Colors.white, accent, 0.2)!.withValues(alpha: 0.42),
          const Color(0x55FFE066),
          const Color(0x449B6BFF),
          const Color(0x443D8BDB),
          Color.lerp(Colors.white, accent, 0.35)!.withValues(alpha: 0.28),
          Colors.transparent,
        ];
        stops = const [0.05, 0.28, 0.4, 0.52, 0.64, 0.78, 0.95];
      case 4:
        colors = [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.28),
          accent.withValues(alpha: 0.32),
          Color.lerp(
            accent,
            const Color(0xFFE0A33C),
            0.45,
          )!.withValues(alpha: 0.22),
          Colors.transparent,
        ];
        stops = const [0.1, 0.35, 0.5, 0.65, 0.9];
      case 3:
        colors = [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.22),
          accent.withValues(alpha: 0.2),
          Colors.transparent,
        ];
        stops = const [0.12, 0.42, 0.58, 0.88];
      case 2:
        colors = [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.18),
          Colors.transparent,
        ];
        stops = const [0.15, 0.48, 0.85];
      default:
        colors = [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.12),
          Colors.transparent,
        ];
        stops = const [0.2, 0.5, 0.8];
    }

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            key: const ValueKey('collectible-foil'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: begin,
                end: end,
                colors: colors,
                stops: stops,
              ),
            ),
          ),
          if (rarity >= 4)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(mx * 0.7, my * 0.55 - 0.2),
                  radius: 0.85,
                  colors: [
                    Colors.white.withValues(alpha: rarity >= 5 ? 0.22 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Collectible card with accelerometer (or pointer) perspective tilt.
class GyroTiltCard extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final Color borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final CardMotionController? motion;

  /// 1.0 = full detail tilt. Ignored when [enableTilt] is false.
  final double intensity;

  /// Procedural foil uniqueness (defaults to border color hash).
  final int? seed;

  /// Drives foil material tier (1–5).
  final int rarity;

  /// Tint for foil / rarity gloss.
  final Color? foilAccent;

  /// When true, collapses parallax offsets (LocalStore reduced motion).
  final bool reduceParallax;

  /// Gyro / drag / foil motion — only true on open/detail (or pack reveal).
  /// Grids stay flat with crown art still visible.
  final bool enableTilt;

  final CardFrameShape frameShape;

  const GyroTiltCard({
    super.key,
    required this.child,
    this.width = 148,
    this.height = 208,
    this.borderColor = AppColors.line,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.motion,
    this.intensity = 1.0,
    this.seed,
    this.rarity = 2,
    this.foilAccent,
    this.reduceParallax = false,
    this.enableTilt = false,
    this.frameShape = CardFrameShape.relic,
  });

  @override
  State<GyroTiltCard> createState() => _GyroTiltCardState();
}

class _GyroTiltCardState extends State<GyroTiltCard>
    with WidgetsBindingObserver {
  late final CardMotionController _motion =
      widget.motion ?? CardMotionController();
  late final bool _ownsMotion = widget.motion == null;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionState();
  }

  @override
  void didUpdateWidget(covariant GyroTiltCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionState();
  }

  void _syncMotionState() {
    _motionDisabled = !widget.enableTilt ||
        widget.reduceParallax ||
        MediaQuery.disableAnimationsOf(context);
    if (_motionDisabled) {
      _motion.pause();
    } else {
      _motion.start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_motionDisabled) _motion.resume();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _motion.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsMotion) _motion.dispose();
    super.dispose();
  }

  Matrix4 _transform(double intensity) {
    final dx = _motion.x * intensity;
    final dy = _motion.y * intensity;
    final maxDeg = 16.0 * intensity;
    final rx = (dy * 16).clamp(-maxDeg, maxDeg) * (math.pi / 180);
    final ry = (dx * 16).clamp(-maxDeg, maxDeg) * (math.pi / 180);
    return Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateX(rx)
      ..rotateY(ry);
  }

  @override
  Widget build(BuildContext context) {
    final systemReduce = MediaQuery.disableAnimationsOf(context);
    final reduce =
        !widget.enableTilt || widget.reduceParallax || systemReduce;
    final intensity = reduce ? 0.0 : widget.intensity;
    final seed = widget.seed ?? cardSeed(widget.borderColor.toString());
    final foilAccent = widget.foilAccent ?? widget.borderColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : widget.width;
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : widget.height;
        return AnimatedBuilder(
          animation: _motion,
          builder: (context, _) {
            final shadowDx = _motion.x * 10 * intensity;
            final shadowDy = 10 + _motion.y * 6 * intensity;
            final edgeOffset = Offset(
              -2.5 - _motion.x * 3.5 * intensity,
              5.5 - _motion.y * 2.5 * intensity,
            );
            return GestureDetector(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onPanUpdate:
                  widget.enableTilt && !reduce ? (d) => _motion.drag(d.delta) : null,
              onPanEnd:
                  widget.enableTilt && !reduce ? (_) => _motion.resetDrag() : null,
              child: Transform(
                key: const ValueKey('collectible-card-transform'),
                transform: _transform(intensity),
                alignment: Alignment.center,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Transform.translate(
                          key: const ValueKey('collectible-card-edge'),
                          offset: edgeOffset,
                          child: ClipPath(
                            clipper: _CardFrameClipper(widget.frameShape),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                  const Color(0xFF06070B),
                                  widget.borderColor,
                                  0.28,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.62),
                                    blurRadius: 24,
                                    offset: Offset(shadowDx, shadowDy + 5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: ClipPath(
                          clipper: _CardFrameClipper(widget.frameShape),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.borderColor.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CardMotionScope(
                              motion: _motion,
                              intensity: intensity,
                              reduceParallax: reduce,
                              seed: seed,
                              rarity: widget.rarity,
                              foilAccent: foilAccent,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  RepaintBoundary(child: widget.child),
                                  if (intensity > 0) const CardFoilOverlay(),
                                  CustomPaint(
                                    painter: _CardFramePainter(
                                      shape: widget.frameShape,
                                      color: widget.selected
                                          ? AppColors.orange
                                          : widget.borderColor,
                                      width: widget.selected ? 3 : 1.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CardFrameClipper extends CustomClipper<Path> {
  final CardFrameShape shape;
  const _CardFrameClipper(this.shape);

  @override
  Path getClip(Size size) {
    if (shape == CardFrameShape.relic) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    }
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * .18, 0)
      ..lineTo(w * .82, 0)
      ..lineTo(w, h * .09)
      ..lineTo(w * .965, h * .79)
      ..lineTo(w * .72, h * .93)
      ..lineTo(w * .5, h)
      ..lineTo(w * .28, h * .93)
      ..lineTo(w * .035, h * .79)
      ..lineTo(0, h * .09)
      ..close();
  }

  @override
  bool shouldReclip(covariant _CardFrameClipper oldClipper) =>
      oldClipper.shape != shape;
}

class _CardFramePainter extends CustomPainter {
  final CardFrameShape shape;
  final Color color;
  final double width;
  const _CardFramePainter({
    required this.shape,
    required this.color,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _CardFrameClipper(
      shape,
    ).getClip(size).transform(Matrix4.diagonal3Values(.985, .99, 1).storage);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CardFramePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.width != width;
}

Color rarityBorder(int rarity) {
  switch (rarity.clamp(1, 5)) {
    case 5:
      return const Color(0xFFE0A33C);
    case 4:
      return const Color(0xFF9B6BFF);
    case 3:
      return const Color(0xFF3D8BDB);
    case 2:
      return const Color(0xFF2BB673);
    default:
      return AppColors.line;
  }
}

Color kindAccent(String kind) {
  switch (kind) {
    case 'goal':
      return AppColors.orange;
    case 'red':
      return const Color(0xFFD8392B);
    case 'yellow':
      return const Color(0xFFE0A33C);
    case 'corner':
      return const Color(0xFF3D8BDB);
    case 'market-swing':
      return const Color(0xFF2BB673);
    default:
      return AppColors.inkSoft;
  }
}

String kindGlyph(String kind) {
  switch (kind) {
    case 'goal':
      return '⚽';
    case 'red':
      return '🟥';
    case 'yellow':
      return '🟨';
    case 'corner':
      return '⛳';
    case 'market-swing':
      return '📈';
    default:
      return '✦';
  }
}

IconData kindIcon(String kind) {
  switch (kind) {
    case 'goal':
      return Icons.sports_soccer_rounded;
    case 'corner':
      return Icons.flag_rounded;
    case 'market-swing':
      return Icons.show_chart_rounded;
    case 'red':
    case 'yellow':
      return Icons.shield_rounded;
    default:
      return Icons.bolt_rounded;
  }
}

@immutable
class CollectibleVisualSpec {
  final String assetPath;
  final Color accent;
  final int seed;
  final int rarity;
  final CardFrameShape frameShape;
  final PortraitAsset? portrait;
  final RarityMaterial rarityMaterial;
  final CollectibleLayerProfile layerProfile;

  const CollectibleVisualSpec({
    required this.assetPath,
    required this.accent,
    required this.seed,
    required this.rarity,
    this.frameShape = CardFrameShape.relic,
    this.portrait,
    this.rarityMaterial = RarityMaterial.gloss,
    this.layerProfile = CollectibleLayerProfile.moment,
  });

  factory CollectibleVisualSpec.moment({
    required String id,
    required String kind,
    required int rarity,
  }) {
    final normalized = kind.toLowerCase();
    final asset = switch (normalized) {
      'goal' => 'assets/cards/goal.svg',
      'red' || 'yellow' || 'card' => 'assets/cards/discipline.svg',
      'corner' => 'assets/cards/corner.svg',
      'market-swing' => 'assets/cards/market.svg',
      'substitution' || 'sub' => 'assets/cards/substitution.svg',
      _ => 'assets/cards/stadium.svg',
    };
    return CollectibleVisualSpec(
      assetPath: asset,
      accent: kindAccent(normalized),
      seed: cardSeed(id),
      rarity: rarity.clamp(1, 5),
      rarityMaterial: RarityMaterial.values[(rarity.clamp(1, 5) - 1)],
    );
  }
}

/// Moment collectible — cinematic dark broadcast plaque with layered parallax.
class MomentCardFace extends StatelessWidget {
  final String title;
  final String matchLabel;
  final String kind;
  final int rarity;
  final int minute;
  final bool calledIt;
  final String? imageUrl, playerId, playerName, teamCode, artKey;

  const MomentCardFace({
    super.key,
    required this.title,
    required this.matchLabel,
    required this.kind,
    required this.rarity,
    required this.minute,
    required this.calledIt,
    this.imageUrl,
    this.playerId,
    this.playerName,
    this.teamCode,
    this.artKey,
  });

  @override
  Widget build(BuildContext context) {
    final seed = cardSeed('${artKey ?? ''}|$title|$matchLabel|$kind|$minute');
    final spec = CollectibleVisualSpec.moment(
      id: '${artKey ?? ''}|$title|$matchLabel|$kind|$minute',
      kind: kind,
      rarity: rarity,
    );
    final accent = spec.accent;
    final rng = math.Random(seed);
    final auroraX = -0.15 + rng.nextDouble() * 0.55;
    final auroraY = -0.55 + rng.nextDouble() * 0.35;
    final diagonal = -0.35 + rng.nextDouble() * 0.7;
    final headline = kind.toLowerCase() == 'corner'
        ? null
        : (playerName?.isNotEmpty == true ? playerName! : title);
    final portrait = portraitForPlayerId(playerId);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // Deep — cinematic base + seeded aurora
        ParallaxLayer(
          depth: 16,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: 220,
              height: 320,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-0.8, -1),
                        end: Alignment(0.9 + diagonal * 0.2, 1),
                        colors: [
                          AppColors.ink,
                          Color.lerp(AppColors.inkSoft, accent, 0.28)!,
                          const Color(0xFF0A0908),
                        ],
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: 0.26,
                    child: SvgPicture.asset(
                      'assets/cards/stadium.svg',
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                    ),
                  ),
                  CustomPaint(
                    painter: _RelicPatternPainter(
                      seed: seed,
                      color: accent,
                      rarity: rarity,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(diagonal - 0.4, -1),
                        end: Alignment(diagonal + 0.6, 1),
                        colors: [
                          Colors.transparent,
                          accent.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                        stops: const [0.25, 0.5, 0.78],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(auroraX, auroraY),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: 0.38),
                            accent.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Mid — verified player cutout or event sculpture.
        ParallaxLayer(
          debugLabel: 'event-subject',
          depth: 5,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: 200,
              height: 290,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _EventRelic(spec: spec),
                  if (portrait != null ||
                      (imageUrl != null && imageUrl!.isNotEmpty))
                    ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, .76, 1],
                      ).createShader(rect),
                      child: _PortraitMedia(
                        asset: portrait,
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        fallback: const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Floating trajectory and rarity particles sit above the subject.
        ParallaxLayer(
          debugLabel: 'event-particles',
          depth: -8,
          child: CustomPaint(
            painter: _RelicParticlePainter(
              seed: seed,
              color: accent,
              count: 5 + rarity * 2,
            ),
          ),
        ),

        // Film vignette (fixed to card plane)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.ink.withValues(alpha: 0.35),
                Colors.transparent,
                AppColors.ink.withValues(alpha: 0.2),
                AppColors.ink.withValues(alpha: 0.94),
              ],
              stops: const [0.0, 0.28, 0.52, 1],
            ),
          ),
        ),

        // Near — raised rarity crest and orbital lens.
        ParallaxLayer(
          debugLabel: 'event-crest',
          depth: -8,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 8 + (seed % 12).toDouble(),
                right: 10,
                child: Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: .78),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .5),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    spec.assetPath,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 48,
                right: -24,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35),
                      width: 1.4,
                    ),
                    color: accent.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ],
          ),
        ),

        // HUD
        ParallaxLayer(
          depth: -14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '★' * rarity.clamp(1, 5),
                      style: TextStyle(
                        color: rarityBorder(rarity),
                        fontSize: 12,
                        letterSpacing: -1,
                        shadows: [
                          Shadow(
                            color: rarityBorder(rarity).withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (teamCode != null && teamCode!.isNotEmpty)
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.cream.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          _teamFlags[teamCode!.toUpperCase()] ?? '🏳️',
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'MOMENT',
                  style: label(
                    color: AppColors.mutInk,
                    size: 9,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                if (headline != null)
                  Text(
                    headline,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: display(19, color: AppColors.cream),
                  ),
                const Spacer(),
                Text(
                  matchLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(color: AppColors.mutInk, size: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  "$minute' · ${kind.toUpperCase()}",
                  style: label(color: accent, size: 9, weight: FontWeight.w800),
                ),
                if (calledIt) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.orange),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.orange.withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      'CALLED IT',
                      style: label(
                        color: AppColors.orangeBright,
                        size: 8,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EventRelic extends StatelessWidget {
  final CollectibleVisualSpec spec;

  const _EventRelic({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 176,
          height: 176,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                spec.accent.withValues(alpha: .42),
                spec.accent.withValues(alpha: .08),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: spec.accent.withValues(alpha: .36),
                blurRadius: 34,
              ),
            ],
          ),
        ),
        Transform.rotate(
          angle: ((spec.seed % 17) - 8) * math.pi / 360,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: SvgPicture.asset(
              spec.assetPath,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelicPatternPainter extends CustomPainter {
  final int seed, rarity;
  final Color color;

  const _RelicPatternPainter({
    required this.seed,
    required this.color,
    required this.rarity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final line = Paint()
      ..color = color.withValues(alpha: .08 + rarity * .012)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 9; i++) {
      final y = size.height * (.08 + i * .105);
      final offset = (rng.nextDouble() - .5) * 20;
      canvas.drawLine(
        Offset(-20, y + offset),
        Offset(size.width + 20, y),
        line,
      );
    }
    final ring = Paint()
      ..color = color.withValues(alpha: .13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rarity >= 4 ? 2 : 1;
    canvas.drawCircle(
      Offset(size.width * .54, size.height * .46),
      size.shortestSide * .36,
      ring,
    );
    canvas.drawCircle(
      Offset(size.width * .54, size.height * .46),
      size.shortestSide * .26,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _RelicPatternPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.rarity != rarity ||
      oldDelegate.color != color;
}

class _RelicParticlePainter extends CustomPainter {
  final int seed, count;
  final Color color;

  const _RelicParticlePainter({
    required this.seed,
    required this.color,
    required this.count,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed ^ 0xA53C);
    for (var i = 0; i < count; i++) {
      final center = Offset(
        size.width * (.08 + rng.nextDouble() * .84),
        size.height * (.18 + rng.nextDouble() * .55),
      );
      final radius = 1.1 + rng.nextDouble() * (i.isEven ? 2.4 : 1.2);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Color.lerp(
            color,
            Colors.white,
            rng.nextDouble() * .7,
          )!.withValues(alpha: .28 + rng.nextDouble() * .38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RelicParticlePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.count != count ||
      oldDelegate.color != color;
}

/// Compact, image-first player face for Duel hand and round reveals.
/// The full collectible HUD is intentionally avoided at these small sizes.
class DuelPlayerCardFace extends StatelessWidget {
  final String? playerId;
  final String name;
  final String teamCode;
  final String position;
  final String? imageUrl;
  final Map<String, int> axes;
  final String? activeAxis;

  const DuelPlayerCardFace({
    super.key,
    required this.name,
    required this.teamCode,
    required this.position,
    required this.axes,
    this.playerId,
    this.imageUrl,
    this.activeAxis,
  });

  @override
  Widget build(BuildContext context) {
    final accent = teamColor(teamCode);
    final portrait = portraitForPlayerId(playerId);
    final hasPortrait =
        portrait != null || (imageUrl != null && imageUrl!.isNotEmpty);
    final seed = cardSeed('$name|$teamCode|$position');
    final rating = axes.isEmpty
        ? 70 + (seed % 25)
        : (axes.values.reduce((a, b) => a + b) / axes.length).round().clamp(
            60,
            99,
          );
    final axisValue = activeAxis == null ? null : axes[activeAxis];
    final surname = name.trim().split(RegExp(r'\s+')).last.toUpperCase();

    return LayoutBuilder(
      builder: (context, box) {
        final tiny = box.maxWidth < 95;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF162B25), accent, .48)!,
                    const Color(0xFF06100C),
                  ],
                ),
              ),
            ),
            Opacity(
              opacity: .14,
              child: SvgPicture.asset(
                'assets/cards/stadium.svg',
                fit: BoxFit.cover,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
            Positioned(
              left: -6,
              right: -6,
              top: tiny ? 8 : 5,
              bottom: tiny ? 29 : 35,
              child: hasPortrait
                  ? _PortraitMedia(
                      asset: portrait,
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallback: _duelFallback(accent, tiny),
                    )
                  : _duelFallback(accent, tiny),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x22000000),
                    Color(0xF207100C),
                  ],
                  stops: [0.35, 0.62, 1],
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                width: tiny ? 29 : 34,
                height: tiny ? 25 : 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xE607100C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.orangeBright.withValues(alpha: .75),
                  ),
                ),
                child: Text(
                  '$rating',
                  style: display(
                    tiny ? 15 : 18,
                    color: AppColors.cream,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 7,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: tiny ? 4 : 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  position.toUpperCase(),
                  style: label(
                    color: Colors.white,
                    size: tiny ? 7 : 8,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 7,
              right: 7,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(
                      tiny ? 11 : 14,
                      color: AppColors.cream,
                      spacing: .2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        teamCode,
                        style: label(
                          color: accent,
                          size: tiny ? 7 : 8,
                          weight: FontWeight.w900,
                        ),
                      ),
                      if (axisValue != null) ...[
                        const Spacer(),
                        Text(
                          '${_axisShort(activeAxis!)} $axisValue',
                          style: label(
                            color: AppColors.orangeBright,
                            size: tiny ? 7 : 8,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _duelFallback(Color accent, bool tiny) => Center(
    child: Container(
      width: tiny ? 42 : 58,
      height: tiny ? 42 : 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: .72),
        border: Border.all(color: Colors.white38),
      ),
      alignment: Alignment.center,
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: display(tiny ? 22 : 30, color: Colors.white),
      ),
    ),
  );

  String _axisShort(String axis) => switch (axis) {
    'finishing' => 'FIN',
    'chaos' => 'CHA',
    'clutch' => 'CLU',
    'marketShock' => 'MKT',
    'aura' => 'AUR',
    _ => axis.substring(0, math.min(3, axis.length)).toUpperCase(),
  };
}

/// Player collectible — athletic trading card with Matchics-style HUD.
/// Crown frame uses safe insets so rating / name / axis chips never clip.
class PlayerCardFace extends StatelessWidget {
  final String? playerId;
  final String name;
  final String teamCode;
  final String position;
  final String? imageUrl;
  final Map<String, int> axes;
  final int? rating;
  final CardFrameShape frameShape;

  const PlayerCardFace({
    super.key,
    required this.name,
    required this.teamCode,
    required this.position,
    required this.axes,
    this.playerId,
    this.imageUrl,
    this.rating,
    this.frameShape = CardFrameShape.relic,
  });

  bool get _crown => frameShape == CardFrameShape.stadiumCrown;

  (String, String) get _nameParts {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (
        parts.first.toUpperCase(),
        parts.sublist(1).join(' ').toUpperCase(),
      );
    }
    return ('', name.toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    final accent = teamColor(teamCode);
    final seed = cardSeed('$name|$teamCode|$position');
    final burstAngle = ((seed % 60) - 30) * math.pi / 180;
    final displayRating =
        rating ??
        (axes.isEmpty
            ? 70 + (seed % 25)
            : (axes.values.reduce((a, b) => a + b) / axes.length).round().clamp(
                60,
                99,
              ));
    final (first, last) = _nameParts;
    final pos = position.toUpperCase();
    final portrait = portraitForPlayerId(playerId);
    final hasPortrait =
        portrait != null || (imageUrl != null && imageUrl!.isNotEmpty);
    final hudPad = _crown
        ? const EdgeInsets.fromLTRB(20, 18, 20, 44)
        : const EdgeInsets.fromLTRB(12, 12, 12, 16);
    final crestAlign = _crown ? const Alignment(.42, -.42) : const Alignment(.62, -.48);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // Far — stadium field + burst
        ParallaxLayer(
          debugLabel: 'player-stadium',
          depth: 16,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: 220,
              height: 320,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(const Color(0xFFE8F4FF), accent, 0.35)!,
                          Color.lerp(const Color(0xFFB8E0C8), accent, 0.45)!,
                          Color.lerp(AppColors.inkSoft, accent, 0.55)!,
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.rotate(
                      angle: burstAngle,
                      child: CustomPaint(
                        size: const Size(240, 240),
                        painter: _BurstPainter(
                          color: accent.withValues(alpha: 0.55),
                          seed: seed,
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: .18,
                    child: SvgPicture.asset(
                      'assets/cards/stadium.svg',
                      fit: BoxFit.cover,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  if (hasPortrait)
                    Opacity(
                      opacity: .25,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            accent,
                            BlendMode.color,
                          ),
                          child: _PortraitMedia(
                            asset: portrait,
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            fallback: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Mid atmosphere bloom
        ParallaxLayer(
          debugLabel: 'player-bloom',
          depth: 11,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.15, -0.35),
                radius: 0.95,
                colors: [
                  accent.withValues(alpha: 0.28),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Ghost silhouette behind subject
        if (hasPortrait)
          ParallaxLayer(
            debugLabel: 'player-silhouette',
            depth: 9,
            child: Transform.translate(
              offset: const Offset(-14, 6),
              child: Opacity(
                opacity: .24,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                  child: _PortraitMedia(
                    asset: portrait,
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    fallback: const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),

        // Main portrait bust
        ParallaxLayer(
          debugLabel: 'player-subject',
          depth: 4,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: 200,
              height: 280,
              child: hasPortrait
                  ? _PortraitMedia(
                      asset: portrait,
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      fallback: _fallbackMark(accent),
                    )
                  : _fallbackMark(accent),
            ),
          ),
        ),

        ParallaxLayer(
          debugLabel: 'player-particles',
          depth: -6,
          child: CustomPaint(
            painter: _RelicParticlePainter(
              seed: seed,
              color: accent,
              count: 13,
            ),
          ),
        ),

        // Specular rim that tracks tilt
        ParallaxLayer(
          debugLabel: 'player-specular',
          depth: -8,
          child: const _SpecularRim(),
        ),

        // Soft vignette into name plate
        ParallaxLayer(
          debugLabel: 'player-vignette',
          depth: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.32, 0.55, 1],
              ),
            ),
          ),
        ),

        // Floating team crest
        ParallaxLayer(
          debugLabel: 'player-crest',
          depth: -11,
          child: Align(
            alignment: crestAlign,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Text(
                teamCode,
                style: label(
                  color: Colors.white,
                  size: 10,
                  weight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),

        // Soft oval under the name plate
        ParallaxLayer(
          debugLabel: 'player-plate-shadow',
          depth: 3,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: _crown ? 36 : 10),
              child: Container(
                width: _crown ? 108 : 130,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Closest HUD — crown-safe insets
        ParallaxLayer(
          debugLabel: 'player-hud',
          depth: -16,
          child: Padding(
            padding: hudPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _HudChip(label: '$displayRating', fill: AppColors.ink),
                    const Spacer(),
                    _HudChip(label: pos, fill: AppColors.ink),
                  ],
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _crown ? 148 : double.infinity,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        _crown ? 10 : 12,
                        9,
                        _crown ? 10 : 12,
                        _crown ? 10 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(_crown ? 12 : 4),
                        border: Border(
                          top: BorderSide(
                            color: accent.withValues(alpha: 0.75),
                            width: 2.5,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (first.isNotEmpty)
                            Text(
                              first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: label(
                                color: AppColors.mutInk,
                                size: 8.5,
                                weight: FontWeight.w700,
                              ),
                            ),
                          Text(
                            last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: display(_crown ? 14 : 16, color: AppColors.cream),
                          ),
                          if (axes.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              runSpacing: 4,
                              children: axes.entries.take(4).map((e) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    '${e.key[0].toUpperCase()}${e.value}',
                                    style: body(
                                      color: AppColors.cream,
                                      size: 9.5,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackMark(Color accent) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -.25),
              colors: [
                accent.withValues(alpha: .65),
                Color.lerp(AppColors.ink, accent, .25)!,
                AppColors.ink,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: SvgPicture.asset(
            'assets/cards/player.svg',
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            colorFilter: ColorFilter.mode(
              Color.lerp(Colors.white, accent, .22)!,
              BlendMode.srcIn,
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, .08),
          child: Text(
            teamCode,
            style: display(42, color: AppColors.ink.withValues(alpha: .22)),
          ),
        ),
      ],
    );
  }
}

/// Thin specular streak that slides with device tilt.
class _SpecularRim extends StatelessWidget {
  const _SpecularRim();

  @override
  Widget build(BuildContext context) {
    final scope = CardMotionScope.maybeOf(context);
    final mx = scope?.motion.x ?? 0.0;
    final my = scope?.motion.y ?? 0.0;
    final accent = scope?.foilAccent ?? Colors.white;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.9 + mx * 0.55, -1.1 + my * 0.3),
            end: Alignment(1.0 + mx * 0.35, 0.6 + my * 0.25),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.08),
              Color.lerp(Colors.white, accent, 0.35)!.withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.06),
              Colors.transparent,
            ],
            stops: const [0.15, 0.38, 0.5, 0.62, 0.85],
          ),
        ),
      ),
    );
  }
}

class _PortraitMedia extends StatelessWidget {
  final PortraitAsset? asset;
  final String? imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Widget fallback;

  const _PortraitMedia({
    required this.asset,
    required this.imageUrl,
    required this.fit,
    required this.alignment,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (asset != null) {
      return Image.asset(
        asset!.assetPath,
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: fit,
        alignment: alignment,
        errorWidget: (_, __, ___) => fallback,
        placeholder: (_, __) => fallback,
      );
    }
    return fallback;
  }
}

class SkillCardFace extends StatelessWidget {
  final String name;
  final String description;
  final Map<String, dynamic> effect;

  const SkillCardFace({
    super.key,
    required this.name,
    required this.description,
    required this.effect,
  });

  @override
  Widget build(BuildContext context) {
    final seed = cardSeed('$name|$description|$effect');
    final effectName =
        (effect['type'] ?? (effect.keys.isEmpty ? 'boost' : effect.keys.first))
            .toString()
            .toLowerCase();
    final defensive = effectName.contains('def') || effectName.contains('save');
    final accent = defensive
        ? const Color(0xFF3D8BDB)
        : const Color(0xFFB8FF36);
    final asset = effectName.contains('swap') || effectName.contains('sub')
        ? 'assets/cards/substitution.svg'
        : 'assets/cards/market.svg';
    return Stack(
      fit: StackFit.expand,
      children: [
        ParallaxLayer(
          debugLabel: 'skill-stadium',
          depth: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF08170F),
                  Color.lerp(const Color(0xFF3A1767), accent, .35)!,
                  const Color(0xFF06070B),
                ],
              ),
            ),
          ),
        ),
        ParallaxLayer(
          debugLabel: 'skill-relic',
          depth: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 46, 22, 64),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: .5),
                    accent.withValues(alpha: .08),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SvgPicture.asset(
                  asset,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
        ParallaxLayer(
          debugLabel: 'skill-particles',
          depth: -7,
          child: CustomPaint(
            painter: _RelicParticlePainter(
              seed: seed,
              color: accent,
              count: 12,
            ),
          ),
        ),
        ParallaxLayer(
          debugLabel: 'skill-hud',
          depth: -13,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'SKILL RELIC',
                      style: label(
                        color: accent,
                        size: 9,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    _HudChip(label: 'FX', fill: AppColors.ink),
                  ],
                ),
                const Spacer(),
                Text(
                  name.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: display(19, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: body(color: AppColors.mutInk, size: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CollectibleCardBack extends StatelessWidget {
  final String caption;
  final Color accent;

  const CollectibleCardBack({
    super.key,
    String label = 'FINAL WHISTLE',
    this.accent = const Color(0xFFB8FF36),
  }) : caption = label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3A1767), Color(0xFF101B16), Color(0xFF050608)],
            ),
            border: Border.all(color: accent, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SvgPicture.asset(
            'assets/cards/stadium.svg',
            colorFilter: ColorFilter.mode(
              accent.withValues(alpha: .75),
              BlendMode.srcIn,
            ),
          ),
        ),
        Center(
          child: Transform.rotate(
            angle: -.12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: AppColors.ink.withValues(alpha: .82),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: label(
                  color: Colors.white,
                  size: 8,
                  weight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HudChip extends StatelessWidget {
  final String label;
  final Color fill;

  const _HudChip({required this.label, required this.fill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(label, style: labelStyle()),
    );
  }

  TextStyle labelStyle() => TextStyle(
    fontFamily: kBody,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.6,
  );
}

/// Stylized X / star burst behind player art (seeded geometry).
class _BurstPainter extends CustomPainter {
  final Color color;
  final int seed;

  _BurstPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final arms = 4 + (seed % 2);
    final outer = size.shortestSide * 0.48;
    final inner = outer * (0.28 + (seed % 10) * 0.01);
    final path = Path();
    for (var i = 0; i < arms * 2; i++) {
      final r = i.isEven ? outer : inner;
      final a = (i / (arms * 2)) * math.pi * 2 - math.pi / 2;
      final x = cx + math.cos(a) * r;
      final y = cy + math.sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    final rim = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset(cx, cy), outer * 0.72, rim);
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) =>
      old.color != color || old.seed != seed;
}
