import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

const _reactions = ['⚽', '🔥', '😱', '👏', '🎉', '😤'];

class ChatDock extends StatefulWidget {
  final List<ChatView> chat;
  final void Function(String text) onSend;
  final void Function(String emoji) onReact;
  final bool disabled;
  const ChatDock({
    super.key,
    required this.chat,
    required this.onSend,
    required this.onReact,
    required this.disabled,
  });

  @override
  State<ChatDock> createState() => _ChatDockState();
}

class _ChatDockState extends State<ChatDock> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ChatDock old) {
    super.didUpdateWidget(old);
    if (old.chat.length != widget.chat.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    }
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Expanded(
          child: widget.chat.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Say hi 👋 — react together as the match unfolds.',
                        style: TextStyle(color: AppColors.mut)),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: widget.chat.length,
                  itemBuilder: (context, i) {
                    final m = widget.chat[i];
                    if (m.kind == 'system') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Center(
                          child: Text('— ${m.text} —',
                              style: const TextStyle(fontSize: 11, color: AppColors.mut)),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.avatar, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                  text: '${m.name}  ',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mut)),
                              TextSpan(
                                  text: m.text,
                                  style: TextStyle(
                                      fontSize: m.kind == 'reaction' ? 20 : 14, color: AppColors.text)),
                            ]),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(children: [
            Row(
              children: _reactions
                  .map((r) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: GestureDetector(
                            onTap: widget.disabled ? null : () => widget.onReact(r),
                            child: Container(
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: const Color(0x4D000000),
                                  borderRadius: BorderRadius.circular(9)),
                              child: Text(r, style: const TextStyle(fontSize: 17)),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: !widget.disabled,
                  style: const TextStyle(color: AppColors.text),
                  decoration: fwrInput(widget.disabled ? 'Join the room to chat' : 'Message the room…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              PrimaryButton('Send', onTap: widget.disabled ? null : _send),
            ]),
          ]),
        ),
      ]),
    );
  }
}
