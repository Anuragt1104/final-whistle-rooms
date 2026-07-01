import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';

/// Slim "win chance" meter — the market translator, in plain English.
class WinBar extends StatelessWidget {
  final WinChance win;
  final Team home, away;
  const WinBar({super.key, required this.win, required this.home, required this.away});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('LIVE WIN CHANCE', style: label(color: AppColors.ink, size: 11)),
          const Spacer(),
          Text('plain-English odds', style: body(color: AppColors.mut, size: 11)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 26,
            child: LayoutBuilder(builder: (_, c) {
              final w = c.maxWidth;
              final hw = w * win.home / 100;
              final aw = w * win.away / 100;
              final dw = (w - hw - aw).clamp(0.0, w);
              return Row(children: [
                _seg(hw, '${home.code} ${win.home}%', teamColor(home.code)),
                _seg(dw, 'X ${win.draw}', const Color(0xFF6E665A)),
                _seg(aw, '${win.away}% ${away.code}', teamColor(away.code)),
              ]);
            }),
          ),
        ),
      ]),
    );
  }

  Widget _seg(double width, String text, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      width: width,
      color: color,
      alignment: Alignment.center,
      child: width > 44
          ? Text(text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(fontFamily: kBody, fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white))
          : const SizedBox(),
    );
  }
}

/// Live win-chance timeline — the home side's win probability sampled every
/// match-minute, so you can watch the momentum swing across the game. The area
/// is tinted toward whoever's favoured (above/below the 50% line).
class WinTimeline extends StatelessWidget {
  final List<int> history; // home win-% per minute, 0..100
  final Team home, away;
  const WinTimeline({super.key, required this.history, required this.home, required this.away});

  @override
  Widget build(BuildContext context) {
    if (history.length < 3) return const SizedBox.shrink();
    final homeC = teamColor(home.code);
    final awayC = teamColor(away.code);
    final now = history.last;
    final leader = now >= 50 ? home.code : away.code;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('WIN CHANCE TIMELINE', style: label(color: AppColors.ink, size: 11)),
          const Spacer(),
          Text('$leader on top · ${now >= 50 ? now : 100 - now}%',
              style: label(color: now >= 50 ? homeC : awayC, size: 11, weight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 58, child: CustomPaint(painter: _WinTimelinePainter(history, homeC, awayC), size: Size.infinite)),
        const SizedBox(height: 4),
        Row(children: [
          Text(home.code, style: label(color: homeC, size: 8.5, weight: FontWeight.w800)),
          const Spacer(),
          Text('kick-off  →  now', style: body(color: AppColors.mut, size: 8.5)),
          const Spacer(),
          Text(away.code, style: label(color: awayC, size: 8.5, weight: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

class _WinTimelinePainter extends CustomPainter {
  final List<int> h;
  final Color homeC, awayC;
  _WinTimelinePainter(this.h, this.homeC, this.awayC);

  @override
  void paint(Canvas canvas, Size size) {
    final n = h.length;
    final w = size.width, ht = size.height;
    final mid = ht / 2;
    double x(int i) => n == 1 ? 0 : i / (n - 1) * w;
    double y(int v) => (100 - v) / 100 * ht;

    // 50% baseline (dashed)
    final base = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 1;
    for (double dx = 0; dx < w; dx += 7) {
      canvas.drawLine(Offset(dx, mid), Offset(dx + 3.5, mid), base);
    }

    final line = Path()..moveTo(x(0), y(h[0]));
    for (int i = 1; i < n; i++) {
      line.lineTo(x(i), y(h[i]));
    }

    // tint the area between the line and the 50% line, toward whoever leads
    final poly = Path.from(line)
      ..lineTo(x(n - 1), mid)
      ..lineTo(x(0), mid)
      ..close();
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, w, mid))
      ..drawPath(poly, Paint()..color = homeC.withValues(alpha: 0.20))
      ..restore()
      ..save()
      ..clipRect(Rect.fromLTRB(0, mid, w, ht))
      ..drawPath(poly, Paint()..color = awayC.withValues(alpha: 0.20))
      ..restore();

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // current-value marker
    final last = Offset(x(n - 1), y(h[n - 1]));
    canvas.drawCircle(last, 4, Paint()..color = h[n - 1] >= 50 ? homeC : awayC);
    canvas.drawCircle(last, 4, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_WinTimelinePainter old) => old.h.length != h.length || (h.isNotEmpty && old.h.last != h.last);
}
