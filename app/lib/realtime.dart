/// WebSocket realtime connection.
library;

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class Realtime {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  bool _closedByUs = false;

  /// All inbound server events: {event: string, data: dynamic}
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get connected => _channel != null;

  Future<void> connect(String serverBase, String token) async {
    disconnect();
    _closedByUs = false;

    final wsBase = serverBase
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://');
    final uri = Uri.parse('$wsBase/ws?token=${Uri.encodeQueryComponent(token)}');

    try {
      final ch = WebSocketChannel.connect(uri);
      _channel = ch;
      await ch.ready;
      _sub = ch.stream.listen(
        (raw) {
          try {
            final m = jsonDecode(raw.toString());
            if (m is Map<String, dynamic>) _events.add(m);
          } catch (_) {/* ignore malformed frames */}
        },
        onDone: () => _channel = null,
        onError: (_) => _channel = null,
        cancelOnError: false,
      );
    } catch (_) {
      _channel = null;
    }
  }

  void send(String event, Map<String, dynamic> data) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode({'event': event, 'data': data}));
    } catch (_) {/* offline — REST fallbacks used */}
  }

  void disconnect() {
    _closedByUs = true;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  bool get wasClosedByUs => _closedByUs;
}
