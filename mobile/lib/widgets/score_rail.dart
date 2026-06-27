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
            child: Row(children: [
              _seg(win.home, '${home.code} ${win.home}%', teamColor(home.code)),
              _seg(win.draw, 'X ${win.draw}', const Color(0xFF6E665A)),
              _seg(win.away, '${win.away}% ${away.code}', teamColor(away.code)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _seg(int w, String text, Color color) {
    return Expanded(
      flex: w.clamp(6, 100),
      child: Container(
        color: color,
        alignment: Alignment.center,
        child: Text(w >= 13 ? text : '',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(fontFamily: kBody, fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }
}
