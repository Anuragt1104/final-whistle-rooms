import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme.dart';

/// One fused sensor stream shared by an Album/detail page. This avoids opening
/// an accelerometer subscription for every card in a grid.
class CardMotionController extends ChangeNotifier {
  StreamSubscription<AccelerometerEvent>? _accel;
  StreamSubscription<GyroscopeEvent>? _gyro;
  double _ax = 0, _ay = 0, _gx = 0, _gy = 0, _px = 0, _py = 0;
  bool _started = false;

  double get x => ((-_ax * 0.075) + (_gy * 0.22) + _px).clamp(-1.0, 1.0);
  double get y => ((_ay * 0.055 - 0.28) + (_gx * 0.18) + _py).clamp(-1.0, 1.0);

  void start() {
    if (_started) return;
    _started = true;
    try {
      _accel =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.uiInterval,
          ).listen((e) {
            _ax = _ax * 0.86 + e.x * 0.14;
            _ay = _ay * 0.86 + e.y * 0.14;
            notifyListeners();
          }, onError: (_) {});
      _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen((e) {
            _gx = _gx * 0.78 + e.x * 0.22;
            _gy = _gy * 0.78 + e.y * 0.22;
            notifyListeners();
          }, onError: (_) {});
    } catch (_) {
      // Drag remains available as the deterministic emulator/web fallback.
    }
  }

  void drag(Offset delta) {
    _px = (_px + delta.dx * 0.008).clamp(-1.0, 1.0);
    _py = (_py + delta.dy * 0.008).clamp(-1.0, 1.0);
    notifyListeners();
  }

  void resetDrag() {
    _px = 0;
    _py = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _accel?.cancel();
    _gyro?.cancel();
    super.dispose();
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
  });

  @override
  State<GyroTiltCard> createState() => _GyroTiltCardState();
}

class _GyroTiltCardState extends State<GyroTiltCard> {
  late final CardMotionController _motion =
      widget.motion ?? CardMotionController();
  late final bool _ownsMotion = widget.motion == null;

  @override
  void initState() {
    super.initState();
    _motion.start();
  }

  @override
  void dispose() {
    if (_ownsMotion) _motion.dispose();
    super.dispose();
  }

  Matrix4 get _transform {
    final dx = _motion.x;
    final dy = _motion.y;
    final rx = (dy * 18).clamp(-16.0, 16.0) * (math.pi / 180);
    final ry = (dx * 18).clamp(-16.0, 16.0) * (math.pi / 180);
    return Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateX(rx)
      ..rotateY(ry);
  }

  @override
  Widget build(BuildContext context) {
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
          builder: (context, _) => GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onPanUpdate: (d) => _motion.drag(d.delta),
            onPanEnd: (_) => _motion.resetDrag(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: w,
              height: h,
              transformAlignment: Alignment.center,
              transform: _transform,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.selected
                      ? AppColors.orange
                      : widget.borderColor,
                  width: widget.selected ? 2.5 : 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color.lerp(
                      widget.borderColor,
                      Colors.black,
                      0.55,
                    )!.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 + (_motion.x + 1), -1),
                          end: Alignment(1 + (_motion.x + 1), 1),
                          colors: const [
                            Colors.transparent,
                            Color(0x28FFFFFF),
                            Color(0x159B6BFF),
                            Colors.transparent,
                          ],
                          stops: const [0.12, 0.43, 0.58, 0.88],
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
  }
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

/// Moment collectible face for the Album grid.
class MomentCardFace extends StatelessWidget {
  final String title;
  final String matchLabel;
  final String kind;
  final int rarity;
  final int minute;
  final bool calledIt;
  final String? imageUrl, playerName, teamCode, artKey;

  const MomentCardFace({
    super.key,
    required this.title,
    required this.matchLabel,
    required this.kind,
    required this.rarity,
    required this.minute,
    required this.calledIt,
    this.imageUrl,
    this.playerName,
    this.teamCode,
    this.artKey,
  });

  @override
  Widget build(BuildContext context) {
    final accent = kindAccent(kind);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.ink,
                Color.lerp(AppColors.inkSoft, accent, 0.35)!,
                AppColors.ink,
              ],
            ),
          ),
        ),
        if (imageUrl != null && imageUrl!.isNotEmpty)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => const SizedBox(),
            ),
          )
        else
          Positioned(
            right: -18,
            top: 42,
            child: Transform.rotate(
              angle: -.12,
              child: Icon(
                kind == 'goal'
                    ? Icons.sports_soccer_rounded
                    : kind == 'corner'
                    ? Icons.flag_rounded
                    : kind == 'market-swing'
                    ? Icons.show_chart_rounded
                    : Icons.shield_rounded,
                size: 126,
                color: accent.withValues(alpha: .2),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.ink.withValues(alpha: .18),
                AppColors.ink.withValues(alpha: .9),
              ],
              stops: const [.26, .55, 1],
            ),
          ),
        ),
        Positioned(
          top: -20,
          right: -30,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.22),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '★' * rarity,
                    style: TextStyle(
                      color: rarityBorder(rarity),
                      fontSize: 11,
                      letterSpacing: -1,
                    ),
                  ),
                  const Spacer(),
                  Text(kindGlyph(kind), style: const TextStyle(fontSize: 18)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'MOMENT',
                style: label(
                  color: AppColors.mutInk,
                  size: 9,
                  weight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                playerName?.isNotEmpty == true ? playerName! : title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: display(18, color: AppColors.cream),
              ),
              const Spacer(),
              Text(
                matchLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body(color: AppColors.mutInk, size: 11),
              ),
              const SizedBox(height: 2),
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
                    color: AppColors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.orange),
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
      ],
    );
  }
}

/// Player collectible face — uses roster imageUrl when present.
class PlayerCardFace extends StatelessWidget {
  final String name;
  final String teamCode;
  final String position;
  final String? imageUrl;
  final Map<String, int> axes;

  const PlayerCardFace({
    super.key,
    required this.name,
    required this.teamCode,
    required this.position,
    required this.axes,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final accent = teamColor(teamCode);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _fallbackArt(accent),
            placeholder: (_, __) => _fallbackArt(accent),
          )
        else
          _fallbackArt(accent),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.15),
                Colors.black.withValues(alpha: 0.88),
              ],
              stops: const [0.35, 0.55, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  teamCode,
                  style: label(
                    color: Colors.white,
                    size: 9,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: display(17, color: AppColors.cream),
              ),
              const SizedBox(height: 2),
              Text(
                position.toUpperCase(),
                style: label(color: AppColors.mutInk, size: 9),
              ),
              const SizedBox(height: 8),
              Wrap(
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
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${e.key[0].toUpperCase()}${e.value}',
                      style: body(
                        color: AppColors.cream,
                        size: 10,
                        weight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fallbackArt(Color accent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.ink,
            Color.lerp(AppColors.inkSoft, accent, 0.45)!,
            AppColors.ink,
          ],
        ),
      ),
      child: Center(
        child: Text(
          teamCode,
          style: display(42, color: AppColors.cream.withValues(alpha: 0.25)),
        ),
      ),
    );
  }
}
