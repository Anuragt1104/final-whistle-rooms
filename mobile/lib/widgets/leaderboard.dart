import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';

class Leaderboard extends StatelessWidget {
  final RoomView room;
  final String? meId;
  const Leaderboard({super.key, required this.room, required this.meId});

  String _sideFlag(MemberView m) =>
      m.side == 'home' ? room.fixture.home.flag : m.side == 'away' ? room.fixture.away.flag : '';

  @override
  Widget build(BuildContext context) {
    final members = room.members;
    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('🏆 Room leaderboard', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('${members.length} ${members.length == 1 ? "fan" : "fans"}',
                style: const TextStyle(fontSize: 9, letterSpacing: 1, color: AppColors.mut)),
          ]),
        ),
        ...members.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          final isMe = m.id == meId;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? const Color(0x1AC7F24D) : null,
              border: const Border(bottom: BorderSide(color: AppColors.line, width: 0.5)),
            ),
            child: Row(children: [
              SizedBox(
                width: 20,
                child: Text('${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: i == 0 ? AppColors.gold : AppColors.mut)),
              ),
              const SizedBox(width: 8),
              Text(m.avatar, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(m.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    if (_sideFlag(m).isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(_sideFlag(m), style: const TextStyle(fontSize: 12)),
                    ],
                    if (m.isHost) _tag('HOST', AppColors.mut),
                    if (isMe) _tag('YOU', AppColors.lime),
                  ]),
                  Text(
                    '${m.correct} correct${m.bestStreak >= 2 ? " · best ${m.bestStreak}🔥" : ""}',
                    style: const TextStyle(fontSize: 10, color: AppColors.mut),
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${m.points}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                if (m.streak >= 2)
                  Text('🔥 ${m.streak}', style: const TextStyle(fontSize: 10, color: AppColors.gold)),
              ]),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: chipDecoration(),
          child: Text(text, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color)),
        ),
      );
}
