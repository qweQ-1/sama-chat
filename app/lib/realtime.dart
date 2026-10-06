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
  DateTime? _connectingSince;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _watchdog;

  /// All inbound server events: {event: string, data: dynamic}
  /// 另有合成事件 rt:state = {connected: bool}（连接状态变化时发出）。
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get connected => _channel != null;

  Future<void> connect(String serverBase, String token) async {
    _serverBase = serverBase;
    _token = token;
    _shouldRun = true;
    _attempt = 0;
    _connecting = false;
    _retryTimer?.cancel();
    _startWatchdog();
    await _open();
  }

  /// 强制检查连接（App 回到前台时调用），断开则立即重连。
  /// 连接中超过 20 秒视为卡死（穿透抖动/系统挂起导致握手悬挂），强制重来。
  void ensureConnected() {
    if (!_shouldRun) return;
    if (_connecting) {
      final since = _connectingSince;
      if (since != null && DateTime.now().difference(since).inSeconds < 20) {
        return; // 正常连接中，再等等
      }
      _connecting = false; // 解锁卡死的连接状态
    }
    if (connected) return;
    _attempt = 0;
    _retryTimer?.cancel();
    unawaited(_open());
  }

  /// 看门狗：每 30 秒体检一次，卡死/掉线自动恢复（治"永远显示断开"的毛病）。
  void _startWatchdog() {
    _watchdog ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_shouldRun) return;
      if (_connecting) {
        final since = _connectingSince;
        if (since != null &&
            DateTime.now().difference(since).inSeconds > 20) {
          _connecting = false; // 卡死 → 解锁
        } else {
          return; // 正常连接中
        }
      }
      if (!connected) {
        _attempt = 0;
        _retryTimer?.cancel();
        unawaited(_open());
      }
    });
  }

  Future<void> _open() async {
    if (!_shouldRun || _connecting) return;
    final base = _serverBase;
    final token = _token;
    if (base == null || token == null) return;

    _connecting = true;
    _connectingSince = DateTime.now();
    try {
      _closeChannel();
      // 归一化：去掉尾部斜杠（防止 //ws 之类路径问题）
      final cleanBase = base.trim().replaceAll(RegExp(r'/+$'), '');
      final wsBase = cleanBase
          .replaceFirst(RegExp(r'^https://'), 'wss://')
          .replaceFirst(RegExp(r'^http://'), 'ws://');
      final uri = Uri.parse('$wsBase/ws?token=${Uri.encodeQueryComponent(token)}');

      final ch = WebSocketChannel.connect(uri);
      try {
        // 15 秒连不上就放弃并重试（防止握手悬挂导致永远卡在"连接中"）
        await ch.ready.timeout(const Duration(seconds: 15));
      } catch (_) {
        try {
          await ch.sink.close();
        } catch (_) {}
        rethrow;
      }
      if (!_shouldRun || _channel != null) {
        // 已停止，或已有更新的连接成功 → 丢弃本次
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
    // 重连退避：2s → 5s → 之后封顶 10 秒（恢复更快）
    final secs = _attempt <= 1
        ? 2
        : _attempt <= 3
            ? 5
            : 10;
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
    _watchdog?.cancel();
    _watchdog = null;
    _closeChannel();
  }
}
