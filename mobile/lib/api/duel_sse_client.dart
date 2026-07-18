import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../duel/duel_models.dart';

/// Personalized resumable Duel stream. The bearer identity determines which
/// hidden fields the server may project into each snapshot.
class DuelSseClient {
  final String baseUrl;
  final String duelId;
  final Future<String> Function() tokenProvider;

  http.Client? _client;
  bool _closed = false;
  String? _lastEventId;
  final _views = StreamController<DuelViewModel>.broadcast();
  final _connection = StreamController<bool>.broadcast();

  DuelSseClient({
    required this.baseUrl,
    required this.duelId,
    required this.tokenProvider,
    int? lastVersion,
  }) : _lastEventId = lastVersion == null ? null : '$lastVersion' {
    _loop();
  }

  Stream<DuelViewModel> get views => _views.stream;
  Stream<bool> get connection => _connection.stream;

  Future<void> _loop() async {
    while (!_closed) {
      try {
        final token = await tokenProvider();
        _client = http.Client();
        final request = http.Request(
          'GET',
          Uri.parse('$baseUrl/api/duels/$duelId/stream'),
        );
        request.headers.addAll({
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Authorization': 'Bearer $token',
          if (_lastEventId != null) 'Last-Event-ID': _lastEventId!,
        });
        final response = await _client!.send(request);
        if (response.statusCode >= 400) {
          throw Exception('Duel SSE ${response.statusCode}');
        }
        if (!_connection.isClosed) _connection.add(true);

        var buffer = '';
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          if (_closed) break;
          buffer += chunk.replaceAll('\r\n', '\n');
          int index;
          while ((index = buffer.indexOf('\n\n')) >= 0) {
            final frame = buffer.substring(0, index);
            buffer = buffer.substring(index + 2);
            _handleFrame(frame);
          }
        }
      } catch (_) {
        // Reconnect below. GET refresh on the controller repairs missed state.
      }
      if (_closed) break;
      if (!_connection.isClosed) _connection.add(false);
      await Future.delayed(const Duration(milliseconds: 1200));
    }
  }

  void _handleFrame(String frame) {
    String? data;
    for (final line in frame.split('\n')) {
      if (line.startsWith('id:')) {
        _lastEventId = line.substring(3).trim();
      } else if (line.startsWith('data:')) {
        final part = line.substring(5).trim();
        data = data == null ? part : '$data\n$part';
      }
    }
    if (data == null || data.isEmpty || _views.isClosed) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      final json = Map<String, dynamic>.from(decoded);
      final payload = json['view'] is Map
          ? Map<String, dynamic>.from(json['view'] as Map)
          : json['snapshot'] is Map
          ? Map<String, dynamic>.from(json['snapshot'] as Map)
          : json;
      final view = DuelViewModel.fromJson(payload);
      if (view.id.isNotEmpty) {
        _lastEventId = '${view.version}';
        _views.add(view);
      }
    } catch (_) {
      // Ignore malformed/keepalive frames.
    }
  }

  void close() {
    _closed = true;
    _client?.close();
    _views.close();
    _connection.close();
  }
}
