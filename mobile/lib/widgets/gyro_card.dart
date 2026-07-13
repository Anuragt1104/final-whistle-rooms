import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../theme.dart';

/// Collectible card with accelerometer (or pointer) perspective tilt.
class GyroTiltCard extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final Color borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  const GyroTiltCard({
    super.key,
    required this.child,
    this.width = 148,
    this.height = 208,
    this.borderColor = AppColors.line,
    this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  @override
  State<GyroTiltCard> createState() => _GyroTiltCardState();
}

class _GyroTiltCardState extends State<GyroTiltCard> {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _ax = 0, _ay = 0;
  double _px = 0, _py = 0;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _startGyro();
  }

  Future<void> _startGyro() async {
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        if (!mounted) return;
        setState(() {
          _ax = (_ax * 0.82) + (e.x * 0.18);
          _ay = (_ay * 0.82) + (e.y * 0.18);
        });
      });
      _listening = true;
    } catch (_) {
      _listening = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Matrix4 get _transform {
    final dx = _listening ? (-_ax * 0.12) : _px;
    final dy = _listening ? (_ay * 0.08 - 0.35) : _py;
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
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : widget.width;
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0 ? constraints.maxHeight : widget.height;
        return GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onPanUpdate: _listening
              ? null
              : (d) {
                  setState(() {
                    _px = (_px + d.delta.dx * 0.004).clamp(-1.0, 1.0);
                    _py = (_py + d.delta.dy * 0.004).clamp(-1.0, 1.0);
                  });
                },
          onPanEnd: _listening
              ? null
              : (_) => setState(() {
                    _px = 0;
                    _py = 0;
                  }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: w,
            height: h,
            transformAlignment: Alignment.center,
            transform: _transform,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.selected ? AppColors.orange : widget.borderColor,
                width: widget.selected ? 2.5 : 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(widget.borderColor, Colors.black, 0.55)!.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.child,
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

  const MomentCardFace({
    super.key,
    required this.title,
    required this.matchLabel,
    required this.kind,
    required this.rarity,
    required this.minute,
    required this.calledIt,
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
                  Text('★' * rarity, style: TextStyle(color: rarityBorder(rarity), fontSize: 11, letterSpacing: -1)),
                  const Spacer(),
                  Text(kindGlyph(kind), style: const TextStyle(fontSize: 18)),
                ],
              ),
              const SizedBox(height: 10),
              Text('MOMENT', style: label(color: AppColors.mutInk, size: 9, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: display(18, color: AppColors.cream),
              ),
              const Spacer(),
              Text(matchLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(color: AppColors.mutInk, size: 11)),
              const SizedBox(height: 2),
              Text("$minute' · ${kind.toUpperCase()}", style: label(color: accent, size: 9, weight: FontWeight.w800)),
              if (calledIt) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.orange),
                  ),
                  child: Text('CALLED IT', style: label(color: AppColors.orangeBright, size: 8, weight: FontWeight.w800)),
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
                child: Text(teamCode, style: label(color: Colors.white, size: 9, weight: FontWeight.w800)),
              ),
              const Spacer(),
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(17, color: AppColors.cream)),
              const SizedBox(height: 2),
              Text(position.toUpperCase(), style: label(color: AppColors.mutInk, size: 9)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: axes.entries.take(4).map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${e.key[0].toUpperCase()}${e.value}',
                      style: body(color: AppColors.cream, size: 10, weight: FontWeight.w700),
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
          colors: [AppColors.ink, Color.lerp(AppColors.inkSoft, accent, 0.45)!, AppColors.ink],
        ),
      ),
      child: Center(
        child: Text(teamCode, style: display(42, color: AppColors.cream.withValues(alpha: 0.25))),
      ),
    );
  }
}
