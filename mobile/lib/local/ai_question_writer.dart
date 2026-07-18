import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// LLM rewriter for on-device Micro-Play questions.
///
/// The ENGINE stays authoritative — resolver, option keys, deadlines and
/// points never change; the model only rewrites the question text and option
/// labels into vivid, moment-specific copy. Any missing key / timeout /
/// malformed reply returns null and the local template stands.
///
/// Works OUT OF THE BOX with no key via Pollinations.ai (free, no signup).
/// For a faster provider, build with a key (e.g. free tier at console.groq.com):
///   flutter build apk --dart-define=LLM_API_KEY=gsk_... \
///     --dart-define=LLM_API_URL=https://api.groq.com/openai/v1 \
///     --dart-define=LLM_MODEL=llama-3.3-70b-versatile
class AiQuestionWriter {
  static const _key = String.fromEnvironment('LLM_API_KEY');
  static const _url = String.fromEnvironment(
    'LLM_API_URL',
    defaultValue: 'https://text.pollinations.ai/openai',
  );
  static const _model = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'openai',
  );

  static bool get configured => true;

  static const _system =
      'You write in-match prediction questions for a World Cup watch-party app. '
      'You are given the match situation and a mechanically-generated question with fixed option keys. '
      'Rewrite ONLY the question text and option labels to be vivid, specific to this exact moment — '
      'reference the score, minute, named players, momentum, and stakes when the context provides them. '
      'When intensity is high (goal flurries, comebacks, red cards, chaos), lean hard into the drama — '
      'name the flurry, the chase, the 10-men stakes — without inventing events that are not in context. '
      'Rules: the rewritten question MUST ask for exactly the same thing the original resolves '
      '(same outcome, same deadline minute, same teams/sides per option key); never change what an option key means; '
      'no betting/money language; question under 120 characters; each label under 32 characters; '
      'output only JSON: {"question": string, "options": [{"key": string, "label": string}]} '
      'with exactly the same keys in the same order as given.';

  /// Returns the rewritten question + per-key labels, or null (keep template).
  static Future<({String question, Map<String, String> labels})?> rewrite({
    required String question,
    required List<({String key, String label})> options,
    required Map<String, dynamic> context,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_url/chat/completions'),
            headers: {
              if (_key.isNotEmpty) 'authorization': 'Bearer $_key',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'temperature': 0.8,
              'max_tokens': 400,
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': _system},
                {
                  'role': 'user',
                  'content': jsonEncode({
                    'context': context,
                    'original': {
                      'question': question,
                      'options': [
                        for (final o in options) {'key': o.key, 'label': o.label},
                      ],
                    },
                  }),
                },
              ],
            }),
          )
          // Keyless free tier is slower; a late reply is a harmless no-op
          // because the engine never rewrites locked/answered prompts.
          .timeout(Duration(seconds: _key.isNotEmpty ? 4 : 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final content =
          ((data['choices'] as List?)?.firstOrNull as Map?)?['message']?['content'];
      if (content is! String) return null;
      return _validate(content, options);
    } catch (_) {
      return null;
    }
  }

  static ({String question, Map<String, String> labels})? _validate(
    String content,
    List<({String key, String label})> options,
  ) {
    try {
      var text = content.trim();
      final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(text);
      if (fence != null) text = fence.group(1)!;
      final obj = jsonDecode(text);
      if (obj is! Map) return null;
      final q = obj['question'];
      if (q is! String || q.trim().length < 10 || q.trim().length > 140) {
        return null;
      }
      final opts = obj['options'];
      if (opts is! List || opts.length != options.length) return null;
      final labels = <String, String>{};
      for (final o in opts) {
        if (o is! Map) return null;
        final key = o['key'];
        final label = o['label'];
        if (key is! String || label is! String) return null;
        final trimmed = label.trim();
        if (trimmed.isEmpty || trimmed.length > 40) return null;
        labels[key] = trimmed;
      }
      for (final o in options) {
        if (!labels.containsKey(o.key)) return null;
      }
      if (labels.length != options.length) return null;
      return (question: q.trim(), labels: labels);
    } catch (_) {
      return null;
    }
  }
}
