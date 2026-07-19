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
  final bool embedded;
  const NextSwingCard({
    super.key,
    required this.prompts,
    required this.myPicks,
    required this.onPick,
    this.streak = 0,
    this.bestStreak = 0,
    this.onShare,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final open = prompts
        .where((p) => p.status == 'open' || p.status == 'locked')
        .toList();
    PromptView? main;
    PromptView? quick;
    for (final p in open) {
      if (p.lane == 'quick' && quick == null) {
        quick = p;
      } else if (main == null) {
        main = p;
      } else {
        quick ??= p;
      }
    }
    main ??= open.isNotEmpty ? open.first : null;
    quick = identical(quick, main) ? null : quick;

    final settled = prompts
        .where(
          (p) =>
              p.status == 'settled' ||
              p.status == 'void' ||
              p.status == 'corrected',
        )
        .take(3)
        .toList();

    return Container(
      decoration: embedded ? null : cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: embedded ? Colors.transparent : AppColors.cardAlt,
            child: Row(
              children: [
                Text(
                  'LIVE CALLS',
                  style: label(
                    color: AppColors.ink,
                    size: 11.5,
                    weight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
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
                    '$streak streak${bestStreak > 0 ? " · best $bestStreak" : ""}',
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
          if (main != null)
            _ActivePrompt(
              prompt: main,
              myPick: myPicks[main.id],
              onPick: onPick,
              compact: false,
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Text(
                'The next Live Call opens when the match changes.',
                style: body(color: AppColors.mut, size: 12),
              ),
            ),
          if (quick != null)
            _ActivePrompt(
              prompt: quick,
              myPick: myPicks[quick.id],
              onPick: onPick,
              compact: true,
            ),
          if (settled.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                'SETTLED',
                style: label(
                  color: AppColors.mut,
                  size: 10,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            for (final p in settled)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  p.winningKey != null
                      ? '${p.question} → ${p.options.firstWhere(
                          (o) => o.key == p.winningKey,
                          orElse: () => SwingOption(key: '', label: p.winningKey!),
                        ).label}'
                      : p.question,
                  style: body(color: AppColors.mut, size: 11.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivePrompt extends StatelessWidget {
  final PromptView prompt;
  final String? myPick;
  final void Function(String, String) onPick;
  final bool compact;
  const _ActivePrompt({
    required this.prompt,
    required this.myPick,
    required this.onPick,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final locked = prompt.status == 'locked';
    final total = prompt.tally.values.fold<int>(0, (a, b) => a + b);
    final isBuzz = prompt.category == 'fan-buzz' || prompt.fanBuzzUrl != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, compact ? 0 : 6, 14, compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact || prompt.lane != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                (prompt.lane ?? 'main').toUpperCase(),
                style: label(
                  color: AppColors.mut,
                  size: 9.5,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          if (isBuzz) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                border: Border(
                  left: BorderSide(color: AppColors.orange, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FAN BUZZ',
                    style: label(
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: AppColors.orange,
                    ),
                  ),
                  if (prompt.fanBuzzFact != null)
                    Text(prompt.fanBuzzFact!, style: body(size: 11.5)),
                  if (prompt.fanBuzzUrl != null)
                    Text(
                      prompt.fanBuzzUrl!,
                      style: body(size: 10.5, color: AppColors.mut),
                    ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  prompt.question,
                  style: body(size: compact ? 13 : 15, weight: FontWeight.w800),
                ),
              ),
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
                ? 'Locked — awaiting result'
                : "Locks at ${prompt.locksAtMinute}'",
            style: body(color: AppColors.mut, size: 11.5),
          ),
          const SizedBox(height: 9),
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
                'Locked in. Streaks stack — keep calling them right.',
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
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
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
