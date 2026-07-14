import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/models.dart';
import '../theme.dart';

class NextSwingCard extends StatelessWidget {
  final List<PromptView> prompts;
  final Map<String, String> myPicks;
  final void Function(String promptId, String optionKey) onPick;
  final int streak;
  final int bestStreak;
  final VoidCallback? onShare;
  const NextSwingCard({
    super.key,
    required this.prompts,
    required this.myPicks,
    required this.onPick,
    this.streak = 0,
    this.bestStreak = 0,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    PromptView? active;
    for (final p in prompts) {
      if (p.status == 'open') {
        active = p;
        break;
      }
    }
    if (active == null) {
      final locked = prompts.where((p) => p.status == 'locked');
      if (locked.isNotEmpty) active = locked.first;
    }
    final recent = prompts.where((p) => p.status == 'settled').take(3).toList();

    return Container(
      decoration: cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: AppColors.cardAlt,
            child: Row(
              children: [
                Text(
                  '⚡ LIVE CALLS',
                  style: label(
                    color: AppColors.ink,
                    size: 11.5,
                    weight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                // live streak — build it, share it
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: streak > 0
                        ? AppColors.orange
                        : AppColors.line.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '🔥 $streak${bestStreak > 0 ? "  ·  best $bestStreak" : ""}',
                    style: label(
                      color: streak > 0 ? Colors.white : AppColors.mut,
                      size: 9.5,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                if (onShare != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onShare,
                    child: const Icon(
                      Icons.ios_share_rounded,
                      size: 16,
                      color: AppColors.mut,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (active != null)
            _ActivePrompt(
              prompt: active,
              myPick: myPicks[active.id],
              onPick: onPick,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              child: Text(
                'Waiting for the next verified match update. A new Live Call will appear as play develops.',
                textAlign: TextAlign.center,
                style: body(color: AppColors.mut, size: 13),
              ),
            ),
          if (recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: AppColors.line, height: 18),
                  Text(
                    'RECENT CALLS',
                    style: label(color: AppColors.mut, size: 9),
                  ),
                  const SizedBox(height: 4),
                  ...recent.map((p) {
                    final win = p.options.where((o) => o.key == p.winningKey);
                    final winLabel = win.isNotEmpty ? win.first.label : 'void';
                    final mine = myPicks[p.id];
                    final correct = mine != null && mine == p.winningKey;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.question,
                              overflow: TextOverflow.ellipsis,
                              style: body(color: AppColors.mut, size: 12),
                            ),
                          ),
                          Text(
                            winLabel,
                            style: body(size: 12, weight: FontWeight.w700),
                          ),
                          if (mine != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              correct ? '✓' : '✗',
                              style: TextStyle(
                                color: correct
                                    ? AppColors.orange
                                    : const Color(0xFFD8392B),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivePrompt extends StatelessWidget {
  final PromptView prompt;
  final String? myPick;
  final void Function(String, String) onPick;
  const _ActivePrompt({
    required this.prompt,
    required this.myPick,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final locked = prompt.status == 'locked';
    final total = prompt.tally.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(prompt.question, style: display(18))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${prompt.basePoints}',
                  style: label(color: AppColors.orangeBright, size: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            locked
                ? '🔒 Locked — awaiting result'
                : "Locks at ${prompt.locksAtMinute}'",
            style: body(color: AppColors.mut, size: 11.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: prompt.options.map((o) {
              final picked = myPick == o.key;
              final share = total == 0
                  ? 0
                  : ((prompt.tally[o.key] ?? 0) / total * 100).round();
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
            Center(
              child: Text(
                'Locked in. Streaks stack — keep calling them right. 🔥',
                style: body(
                  color: AppColors.orange,
                  size: 11.5,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
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
      opacity: disabled && !picked ? 0.55 : 1,
      child: GestureDetector(
        onTap: disabled
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Container(
          decoration: BoxDecoration(
            color: picked ? AppColors.orange : AppColors.cardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: picked ? AppColors.orange : AppColors.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (!picked)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (share / 100).clamp(0, 1),
                    child: Container(color: const Color(0x14E9531E)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 4,
                ),
                child: Column(
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(
                        color: picked ? Colors.white : AppColors.ink,
                        size: 13,
                        weight: FontWeight.w800,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint!,
                        style: body(
                          color: picked ? Colors.white70 : AppColors.mut,
                          size: 10,
                        ),
                      ),
                    Text(
                      '$share%',
                      style: body(
                        color: picked ? Colors.white70 : AppColors.mut,
                        size: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
