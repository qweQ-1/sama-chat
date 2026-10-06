/// WebSocket realtime connection with auto-reconnect.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class Realtime {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  String? _serverBase;
  String? _token;
  bool _shouldRun = false;
  bool _connecting = false;
  int _attempt = 0;
  Timer? _retryTimer;

  /// All inbound server events: {event: string, data: dynamic}
  /// 另有合成事件 rt:state = {connected: bool}（连接状态变化时发出）。
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get connected => _channel != null;

  Future<void> connect(String serverBase, String token) async {
    _serverBase = serverBase;
    _token = token;
    _shouldRun = true;
    _attempt = 0;
    _retryTimer?.cancel();
    await _open();
  }

  /// 强制检查连接（App 回到前台时调用），断开则立即重连。
  void ensureConnected() {
    if (!_shouldRun || connected || _connecting) return;
    _attempt = 0;
    _retryTimer?.cancel();
    unawaited(_open());
  }

  Future<void> _open() async {
    if (!_shouldRun || _connecting) return;
    final base = _serverBase;
    final token = _token;
    if (base == null || token == null) return;

    _connecting = true;
    try {
      _closeChannel();
      final wsBase = base
          .replaceFirst(RegExp(r'^https://'), 'wss://')
          .replaceFirst(RegExp(r'^http://'), 'ws://');
      final uri = Uri.parse('$wsBase/ws?token=${Uri.encodeQueryComponent(token)}');

      final ch = WebSocketChannel.connect(uri);
      try {
        await ch.ready;
      } catch (_) {
        try {
          await ch.sink.close();
        } catch (_) {}
        rethrow;
      }
      if (!_shouldRun) {
        try {
          await ch.sink.close();
        } catch (_) {}
        return;
      }
      _channel = ch;
      _attempt = 0;
      _events.add({
        'event': 'rt:state',
        'data': {'connected': true},
      });
      _sub = ch.stream.listen(
        (raw) {
          try {
            final m = jsonDecode(raw.toString());
            if (m is Map<String, dynamic>) _events.add(m);
          } catch (_) {/* ignore malformed frames */}
        },
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: false,
      );
    } catch (_) {
      _onClosed();
    } finally {
      _connecting = false;
    }
  }

  void _onClosed() {
    _closeChannel();
    _events.add({
      'event': 'rt:state',
      'data': {'connected': false},
    });
    if (!_shouldRun) return;
    _attempt++;
    final secs = _attempt <= 1
        ? 2
        : _attempt <= 3
            ? 5
            : _attempt <= 6
                ? 15
                : 30;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: secs), _open);
  }

  void _closeChannel() {
    _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        ch.sink.close();
      } catch (_) {}
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
    _shouldRun = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _closeChannel();
  }
}
