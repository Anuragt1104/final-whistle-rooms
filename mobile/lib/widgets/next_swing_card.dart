import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

class NextSwingCard extends StatelessWidget {
  final List<PromptView> prompts;
  final Map<String, String> myPicks;
  final void Function(String promptId, String optionKey) onPick;
  const NextSwingCard({super.key, required this.prompts, required this.myPicks, required this.onPick});

  @override
  Widget build(BuildContext context) {
    PromptView? active;
    for (final p in prompts) {
      if (p.status == 'open') {
        active = p;
        break;
      }
    }
    active ??= prompts.where((p) => p.status == 'locked').isNotEmpty
        ? prompts.firstWhere((p) => p.status == 'locked')
        : null;
    final recent = prompts.where((p) => p.status == 'settled').take(3).toList();

    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('⚡ Next Swing', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('SKILL · POINTS ONLY',
                style: TextStyle(fontSize: 9, letterSpacing: 1, color: AppColors.mut)),
          ]),
        ),
        if (active != null)
          _ActivePrompt(prompt: active, myPick: myPicks[active.id], onPick: onPick)
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            child: Text('No open call right now — the next prompt drops as the match develops.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.mut, fontSize: 13)),
          ),
        if (recent.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RECENT CALLS',
                  style: TextStyle(fontSize: 9, letterSpacing: 1, color: AppColors.mut)),
              const SizedBox(height: 4),
              ...recent.map((p) {
                final win = p.options.where((o) => o.key == p.winningKey);
                final winLabel = win.isNotEmpty ? win.first.label : 'void';
                final mine = myPicks[p.id];
                final correct = mine != null && mine == p.winningKey;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(p.question,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.mut)),
                    ),
                    Text(winLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    if (mine != null) ...[
                      const SizedBox(width: 4),
                      Text(correct ? '✓' : '✗',
                          style: TextStyle(color: correct ? AppColors.lime : AppColors.away)),
                    ],
                  ]),
                );
              }),
            ]),
          ),
      ]),
    );
  }
}

class _ActivePrompt extends StatelessWidget {
  final PromptView prompt;
  final String? myPick;
  final void Function(String, String) onPick;
  const _ActivePrompt({required this.prompt, required this.myPick, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final locked = prompt.status == 'locked';
    final total = prompt.tally.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(prompt.question, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          AppChip('+${prompt.basePoints}', color: AppColors.gold),
        ]),
        const SizedBox(height: 2),
        Text(locked ? '🔒 Locked — awaiting result' : "Locks at ${prompt.locksAtMinute}'",
            style: const TextStyle(fontSize: 11, color: AppColors.mut)),
        const SizedBox(height: 12),
        Row(
          children: prompt.options.map((o) {
            final picked = myPick == o.key;
            final share = total == 0 ? 0 : ((prompt.tally[o.key] ?? 0) / total * 100).round();
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _OptionButton(
                  label: o.label,
                  hint: o.hint,
                  share: share,
                  picked: picked,
                  disabled: locked || myPick != null,
                  onTap: () => onPick(prompt.id, o.key),
                ),
              ),
            );
          }).toList(),
        ),
        if (myPick != null && !locked) ...[
          const SizedBox(height: 8),
          const Center(
            child: Text('Locked in. Streak rewards stack — keep calling them right. 🔥',
                style: TextStyle(fontSize: 11, color: AppColors.lime)),
          ),
        ],
      ]),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final String? hint;
  final int share;
  final bool picked, disabled;
  final VoidCallback onTap;
  const _OptionButton({
    required this.label,
    required this.hint,
    required this.share,
    required this.picked,
    required this.disabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled && !picked ? 0.6 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            color: picked ? const Color(0x26C7F24D) : const Color(0x33000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: picked ? AppColors.lime : AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (share / 100).clamp(0, 1),
                child: Container(color: const Color(0x0DFFFFFF)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(children: [
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (hint != null)
                  Text(hint!, style: const TextStyle(fontSize: 10, color: AppColors.mut)),
                Text('$share% of room', style: const TextStyle(fontSize: 10, color: AppColors.mut)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
