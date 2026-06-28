import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

String _ago(int ts) {
  if (ts == 0) return '';
  final d = DateTime.now().millisecondsSinceEpoch - ts;
  if (d < 45000) return 'now';
  if (d < 3600000) return '${(d / 60000).round()}m';
  return '${(d / 3600000).round()}h';
}

/// Inline chat feed (used inside the live room scroll).
class ChatFeed extends StatelessWidget {
  final List<ChatView> chat;
  final String hostId;
  const ChatFeed({super.key, required this.chat, required this.hostId});
  @override
  Widget build(BuildContext context) {
    if (chat.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Text('Say something 👋 — the terrace reacts together as the match unfolds.',
            textAlign: TextAlign.center, style: body(color: AppColors.mut, size: 13)),
      );
    }
    return Column(
      children: chat.map((m) => _ChatRow(key: ValueKey(m.id), m: m, isHost: m.memberId == hostId)).toList(),
    );
  }
}

class _ChatRow extends StatefulWidget {
  final ChatView m;
  final bool isHost;
  const _ChatRow({super.key, required this.m, required this.isHost});
  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    Widget child;
    if (m.kind == 'system') {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Center(child: Text('— ${m.text} —', style: body(color: AppColors.mut, size: 11.5))),
      );
    } else {
      child = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InitialAvatar(name: m.name, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(m.name, style: body(weight: FontWeight.w800, size: 13)),
                if (widget.isHost) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(5)),
                    child: Text('HOST', style: label(color: Colors.white, size: 8, weight: FontWeight.w800)),
                  ),
                ],
                const SizedBox(width: 6),
                Text(_ago(m.ts), style: body(color: AppColors.mut, size: 10.5)),
              ]),
              const SizedBox(height: 2),
              Text(m.text, style: TextStyle(fontFamily: kBody, fontSize: m.kind == 'reaction' ? 22 : 14, color: AppColors.ink, height: 1.3)),
              if (m.reactions.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(
                  children: m.reactions.entries
                      .map((e) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
                            child: Text('${e.key} ${e.value}', style: body(color: AppColors.mut, size: 11, weight: FontWeight.w700)),
                          ))
                      .toList(),
                ),
              ],
            ]),
          ),
        ]),
      );
    }
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(_a),
        child: child,
      ),
    );
  }
}

/// Sticky bottom composer: quick reactions (from the room's pack) + input.
class ChatComposer extends StatefulWidget {
  final void Function(String text) onSend;
  final void Function(String emoji) onReact;
  final bool disabled;
  final List<String> emojis;
  final VoidCallback? onTap;
  const ChatComposer({super.key, required this.onSend, required this.onReact, required this.disabled, required this.emojis, this.onTap});
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _ctrl = TextEditingController();
  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final quick = widget.emojis.take(4).toList();
    final extra = widget.emojis.length - 4;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ...quick.map((r) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Pressable(
                    haptic: HapticFeedbackType.selection,
                    onTap: widget.disabled ? null : () => widget.onReact(r),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
                      child: Text(r, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              )),
          if (extra > 0) ...[
            const SizedBox(width: 6),
            Pressable(
              haptic: HapticFeedbackType.selection,
              onTap: widget.disabled ? null : () => _showMore(context),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
                child: Text('+$extra', style: label(color: AppColors.mut, size: 11)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: !widget.disabled,
              style: body(size: 14),
              decoration: fwrInput(widget.disabled ? 'Join the room to chat' : 'Shout it out…'),
              onTap: widget.onTap,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: widget.disabled ? null : _send,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ]),
    );
  }

  void _showMore(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: widget.emojis
              .map((r) => GestureDetector(
                    onTap: () {
                      widget.onReact(r);
                      Navigator.pop(context);
                    },
                    child: Text(r, style: const TextStyle(fontSize: 30)),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
