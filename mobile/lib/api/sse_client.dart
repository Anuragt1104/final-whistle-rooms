import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Streams live RoomView snapshots from the backend SSE endpoint
/// (GET /api/rooms/{id}/stream), with automatic reconnect.
class RoomSseClient {
  final String baseUrl;
  final String roomId;

  http.Client? _client;
  bool _closed = false;
  final _controller = StreamController<RoomView>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  Stream<RoomView> get rooms => _controller.stream;
  Stream<bool> get connection => _connected.stream;

  RoomSseClient(this.baseUrl, this.roomId) {
    _loop();
  }

  Future<void> _loop() async {
    while (!_closed) {
      try {
        _client = http.Client();
        final req = http.Request('GET', Uri.parse('$baseUrl/api/rooms/$roomId/stream'));
        req.headers['Accept'] = 'text/event-stream';
        req.headers['Cache-Control'] = 'no-cache';
        final resp = await _client!.send(req);
        if (resp.statusCode >= 400) throw Exception('SSE ${resp.statusCode}');
        if (!_closed && !_connected.isClosed) _connected.add(true);

        var buffer = '';
        await for (final chunk in resp.stream.transform(utf8.decoder)) {
          if (_closed) break;
          buffer += chunk;
          int idx;
          while ((idx = buffer.indexOf('\n\n')) >= 0) {
            final frame = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);
            _handleFrame(frame);
          }
        }
      } catch (_) {
        // fall through to reconnect
      }
      if (_closed) break;
      if (!_connected.isClosed) _connected.add(false);
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  void _handleFrame(String frame) {
    if (_closed || _controller.isClosed) return;
    for (final line in frame.split('\n')) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      try {
        final msg = jsonDecode(payload);
        if (msg is Map && msg['type'] == 'state' && msg['room'] != null) {
          _controller.add(RoomView.fromJson(Map<String, dynamic>.from(msg['room'])));
        }
      } catch (_) {
        // ignore malformed frame
      }
    }
  }

  void close() {
    _closed = true;
    _client?.close();
    _controller.close();
    _connected.close();
  }
}
