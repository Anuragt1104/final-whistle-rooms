import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

class ScoreRail extends StatelessWidget {
  final RoomView room;
  const ScoreRail({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final s = room.score;
    final gh = s?.goals.home ?? 0;
    final ga = s?.goals.away ?? 0;
    final phase = s?.phase ?? 0;
    final live = room.status == 'live';
    final clock = phase == 2
        ? 'HT'
        : (phase == 4 || room.status == 'finished')
            ? 'FT'
            : (live && s != null)
                ? "${s.minute}'"
                : '—';

    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _team(room.fixture.home, CrossAxisAlignment.start),
          Expanded(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$gh',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: gh > ga ? Colors.white : AppColors.mut)),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(':', style: TextStyle(fontSize: 26, color: AppColors.mut))),
                Text('$ga',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: ga > gh ? Colors.white : AppColors.mut)),
              ]),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                if (live && phase != 2) ...[const LiveDot(size: 6), const SizedBox(width: 4)],
                Text('$clock · ${phaseLabel(phase)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: live ? AppColors.lime : AppColors.mut)),
              ]),
            ]),
          ),
          _team(room.fixture.away, CrossAxisAlignment.end),
        ]),
        if (s != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            _stat('Corners', s.corners.home, s.corners.away),
            const SizedBox(width: 4),
            _stat('Yellow', s.yellow.home, s.yellow.away),
            const SizedBox(width: 4),
            _stat('Red', s.red.home, s.red.away),
          ]),
        ],
        const SizedBox(height: 14),
        _MomentumMeter(value: room.momentum, homeCode: room.fixture.home.code, awayCode: room.fixture.away.code),
        const SizedBox(height: 12),
        _WinBar(win: room.win, homeCode: room.fixture.home.code, awayCode: room.fixture.away.code),
      ]),
    );
  }

  Widget _team(Team t, CrossAxisAlignment align) {
    return Column(crossAxisAlignment: align, children: [
      Text(t.flag, style: const TextStyle(fontSize: 30)),
      const SizedBox(height: 4),
      Text(t.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      SizedBox(
        width: 86,
        child: Text(t.name,
            textAlign: align == CrossAxisAlignment.start ? TextAlign.start : TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.mut)),
      ),
    ]);
  }

  Widget _stat(String label, int h, int a) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text('$h · $a', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 9, letterSpacing: 0.5, color: AppColors.mut)),
        ]),
      ),
    );
  }
}

class _MomentumMeter extends StatelessWidget {
  final int value;
  final String homeCode, awayCode;
  const _MomentumMeter({required this.value, required this.homeCode, required this.awayCode});
  @override
  Widget build(BuildContext context) {
    final homeShare = ((value + 100) / 2).clamp(0, 100).toDouble();
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(awayCode, style: _lbl),
        const Text('MOMENTUM', style: _lbl),
        Text(homeCode, style: _lbl),
      ]),
      const SizedBox(height: 4),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final center = w / 2;
        final pos = w * homeShare / 100;
        final left = value >= 0 ? center : pos;
        final right = value >= 0 ? pos : center;
        return Stack(children: [
          Container(height: 8, decoration: BoxDecoration(color: AppColors.pitch800, borderRadius: BorderRadius.circular(99))),
          Positioned(left: center - 0.5, child: Container(width: 1, height: 8, color: Colors.white24)),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            left: left,
            child: Container(
              width: (right - left).abs().clamp(2, w),
              height: 8,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: value >= 0 ? AppColors.home : AppColors.away),
            ),
          ),
        ]);
      }),
    ]);
  }

  static const _lbl = TextStyle(fontSize: 9, letterSpacing: 1, color: AppColors.mut, fontWeight: FontWeight.w600);
}

class _WinBar extends StatelessWidget {
  final WinChance win;
  final String homeCode, awayCode;
  const _WinBar({required this.win, required this.homeCode, required this.awayCode});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('WIN CHANCE', style: TextStyle(fontSize: 9, letterSpacing: 1, color: AppColors.mut, fontWeight: FontWeight.w600)),
        Text('live odds, in plain English', style: TextStyle(fontSize: 9, color: AppColors.mut)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 24,
          child: Row(children: [
            _seg(win.home, '$homeCode ${win.home}%', AppColors.home),
            _seg(win.draw, 'X ${win.draw}%', const Color(0xFF5B6B82)),
            _seg(win.away, '${win.away}% $awayCode', AppColors.away),
          ]),
        ),
      ),
    ]);
  }

  Widget _seg(int w, String label, Color color) {
    return Expanded(
      flex: w.clamp(6, 100),
      child: Container(
        color: color,
        alignment: Alignment.center,
        child: Text(w >= 12 ? label : '',
            overflow: TextOverflow.clip,
            maxLines: 1,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF08111F))),
      ),
    );
  }
}
