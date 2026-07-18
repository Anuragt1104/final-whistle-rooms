// Probe: real keyless LLM rewrite through AiQuestionWriter (Dart VM, no
// Flutter bindings needed). Run: dart run tool/ai_writer_probe.dart
import 'package:final_whistle/local/ai_question_writer.dart';

Future<void> main() async {
  final res = await AiQuestionWriter.rewrite(
    question: 'Who wins the next corner?',
    options: [(key: 'home', label: 'USA'), (key: 'away', label: 'BEL')],
    context: {
      'minute': 67,
      'score': 'USA 1-2 BEL',
      'recentGoals': ["64' Lukaku (BEL)"],
      'winChance': {'home': 22, 'draw': 18, 'away': 60},
      'momentum': -40,
      'corners': '3-5',
    },
  );
  if (res == null) {
    print('REWRITE: null (template stands)');
  } else {
    print('REWRITE: ${res.question}');
    for (final e in res.labels.entries) {
      print('  ${e.key} -> ${e.value}');
    }
  }
}

// ignore_for_file: avoid_print
