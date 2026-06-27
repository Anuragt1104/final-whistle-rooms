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
