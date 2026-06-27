import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

class Leaderboard extends StatelessWidget {
  final RoomView room;
  final String? meId;
  const Leaderboard({super.key, required this.room, required this.meId});

  String _sideCode(MemberView m) =>
      m.side == 'home' ? room.fixture.home.code : m.side == 'away' ? room.fixture.away.code : '';

  @override
  Widget build(BuildContext context) {
    final members = room.members;
    final top = members.isNotEmpty ? members.first.points : 0;
    return Container(
      decoration: cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          color: AppColors.cardAlt,
          child: Row(children: [
            Text('TERRACE STANDINGS', style: label(color: AppColors.ink, size: 12, weight: FontWeight.w800)),
            const Spacer(),
            Text('${members.length} ${members.length == 1 ? "fan" : "fans"}', style: label(color: AppColors.mut, size: 9)),
          ]),
        ),
        ...members.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          final isMe = m.id == meId;
          final frac = top > 0 ? (m.points / top).clamp(0.0, 1.0) : 0.0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: const Border(bottom: BorderSide(color: AppColors.line, width: 0.6)),
              color: isMe ? const Color(0x0FE9531E) : null,
            ),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', textAlign: TextAlign.center, style: display(16, color: i == 0 ? AppColors.orange : AppColors.mut))),
              const SizedBox(width: 6),
              InitialAvatar(name: m.name, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(m.name, overflow: TextOverflow.ellipsis, style: body(weight: FontWeight.w800, size: 14))),
                    if (_sideCode(m).isNotEmpty) ...[const SizedBox(width: 5), _tag(_sideCode(m), AppColors.ink)],
                    if (m.isHost) ...[const SizedBox(width: 4), _tag('HOST', AppColors.orange)],
                    if (isMe) ...[const SizedBox(width: 4), _tag('YOU', AppColors.orange)],
                  ]),
                  const SizedBox(height: 5),
                  // mini standings bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 4,
                      backgroundColor: AppColors.cardAlt,
                      valueColor: AlwaysStoppedAnimation(i == 0 ? AppColors.orange : AppColors.ink.withValues(alpha: 0.55)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${m.points}', style: display(17)),
                if (m.streak >= 2) Text('🔥${m.streak}', style: body(color: AppColors.gold, size: 10, weight: FontWeight.w700)),
              ]),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: label(color: color, size: 8, weight: FontWeight.w800)),
      );
}
