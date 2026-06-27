import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

const _reactions = ['🔥', '⚽', '😱', '👏', '🎉', '😤'];

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
  const ChatFeed({super.key, required this.chat});
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
      children: chat.map((m) {
        if (m.kind == 'system') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Center(child: Text('— ${m.text} —', style: body(color: AppColors.mut, size: 11.5))),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InitialAvatar(name: m.name, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(m.name, style: body(weight: FontWeight.w800, size: 13)),
                  const SizedBox(width: 6),
                  Text(_ago(m.ts), style: body(color: AppColors.mut, size: 10.5)),
                ]),
                const SizedBox(height: 2),
                Text(m.text, style: TextStyle(fontFamily: kBody, fontSize: m.kind == 'reaction' ? 22 : 14, color: AppColors.ink, height: 1.3)),
              ]),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

/// Sticky bottom composer: quick reactions + shout-it-out input.
class ChatComposer extends StatefulWidget {
  final void Function(String text) onSend;
  final void Function(String emoji) onReact;
  final bool disabled;
  const ChatComposer({super.key, required this.onSend, required this.onReact, required this.disabled});
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
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ..._reactions.take(4).map((r) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
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
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.disabled ? null : () => _showMore(context),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
              child: Text('+more', style: label(color: AppColors.mut, size: 10)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: !widget.disabled,
              style: body(size: 14),
              decoration: fwrInput(widget.disabled ? 'Join the room to chat' : 'Shout it out…'),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
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
          children: _reactions
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
