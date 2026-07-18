import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../duel/duel_models.dart';
import '../../theme.dart';

class DuelStadiumBackdrop extends StatelessWidget {
  final Widget child;
  final bool dimmed;

  const DuelStadiumBackdrop({
    super.key,
    required this.child,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF020A07), Color(0xFF0A3525), Color(0xFF03110C)],
        stops: [0, .52, 1],
      ),
    ),
    foregroundDecoration: BoxDecoration(
      color: dimmed ? const Color(0x99000000) : Colors.transparent,
    ),
    child: CustomPaint(painter: _StadiumPainter(), child: child),
  );
}

class DuelTurnClock extends StatefulWidget {
  final DateTime? deadline;
  const DuelTurnClock({super.key, this.deadline});

  @override
  State<DuelTurnClock> createState() => _DuelTurnClockState();
}

class _DuelTurnClockState extends State<DuelTurnClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deadline == null) return const SizedBox.shrink();
    final remaining = widget.deadline!.difference(DateTime.now()).inSeconds;
    final safe = math.max(0, remaining);
    final urgent = safe <= 15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xFFD63D2E) : const Color(0xFF173C2C),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '0:${safe.toString().padLeft(2, '0')}',
        style: label(color: Colors.white, size: 10, weight: FontWeight.w900),
      ),
    );
  }
}

class DuelConditionRibbon extends StatelessWidget {
  final DuelViewModel duel;
  const DuelConditionRibbon({super.key, required this.duel});

  @override
  Widget build(BuildContext context) {
    final arena = duel.arena;
    final matching = arena?.conditions.where(
      (c) => c.round == duel.roundNumber,
    );
    final condition = matching != null && matching.isNotEmpty
        ? matching.first
        : null;
    if (arena == null || condition == null) {
      return _ribbon(
        icon: Icons.sports_soccer_rounded,
        title: duel.phase == DuelPhase.axisSelection
            ? 'ATTACKER CHOOSES THE ATTRIBUTE'
            : 'ROUND ${duel.roundNumber} · ${duel.attackerId == duel.fanId ? "YOU ATTACK" : "DEFEND"}',
        detail: 'Game attributes only — not official player statistics',
      );
    }
    return _ribbon(
      icon: Icons.verified_rounded,
      title:
          '${condition.name.toUpperCase()} · ${condition.axis.toUpperCase()}',
      detail:
          "${arena.moment.kind.toUpperCase()} ${arena.moment.minute}' · ${condition.explanation}",
    );
  }

  Widget _ribbon({
    required IconData icon,
    required String title,
    required String detail,
  }) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 14),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xF216251F),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.orange.withValues(alpha: .65)),
      boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 15)],
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.orangeBright, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label(
                  color: AppColors.cream,
                  size: 9.5,
                  weight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: body(color: AppColors.mutInk, size: 9.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StadiumPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x245BE0A4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x245BE0A4), Colors.transparent],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height * .45),
          radius: size.width * .6,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
    final pitch = Rect.fromLTWH(
      18,
      size.height * .18,
      size.width - 36,
      size.height * .62,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pitch, const Radius.circular(10)),
      line,
    );
    canvas.drawLine(
      Offset(pitch.left, pitch.center.dy),
      Offset(pitch.right, pitch.center.dy),
      line,
    );
    canvas.drawCircle(pitch.center, 42, line);
    canvas.drawCircle(pitch.center, 2.5, line..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
