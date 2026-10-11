import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// 全屏通话页：呼出等待 / 来电 / 通话中。由 CallOverlayHost 覆盖显示。
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 每秒刷新通话计时
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.callState;
    if (c == null) return const SizedBox.shrink(); // 由外层移除覆盖层

    final statusText = switch (c.status) {
      'outgoing' => '正在呼叫…',
      'ringing' => '正在响铃…',
      'incoming' => '邀请你语音通话',
      'connecting' => '接听中…',
      'connected' => formatCallDuration(
          DateTime.now().millisecondsSinceEpoch - (c.startedAt ?? 0)),
      _ => '',
    };

    return Material(
      color: const Color(0xFF1B1B22),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Avatar(name: c.peerName, url: c.peerAvatar, size: 112),
            const SizedBox(height: 20),
            Text(c.peerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(statusText,
                style: TextStyle(
                    color: c.status == 'connected'
                        ? Colors.greenAccent
                        : Colors.grey.shade400,
                    fontSize: 15)),
            const Spacer(flex: 3),
            if (c.status == 'incoming') ...[
              // 来电：拒接 / 接听
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: '拒接',
                    onTap: () => context.read<AppState>().rejectIncomingCall(),
                  ),
                  _RoundButton(
                    icon: Icons.call,
                    color: Colors.green,
                    label: '接听',
                    onTap: () async {
                      try {
                        await context.read<AppState>().acceptIncomingCall();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('接听失败：$e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ] else
              // 呼出中 / 通话中
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (c.status == 'connected')
                    _RoundButton(
                      icon: c.muted ? Icons.mic_off : Icons.mic,
                      color: c.muted ? Colors.orange : Colors.white24,
                      label: c.muted ? '取消静音' : '静音',
                      onTap: () => context.read<AppState>().toggleCallMute(),
                    ),
                  _RoundButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: '挂断',
                    onTap: () => context.read<AppState>().endActiveCall(),
                  ),
                ],
              ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ],
    );
  }
}

/// 挂在 MaterialApp.builder 的 Stack 顶层（Navigator 之上）：
/// - callState 有值 → 全屏通话页盖住一切
/// - 通话刚结束且有原因 → 短暂提示，随后移除
/// 本组件自渲染，不依赖 Navigator / ScaffoldMessenger。
class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({super.key});

  @override
  State<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends State<CallOverlayHost> {
  bool _wasActive = false;
  String? _endedMessage;
  Timer? _endedTimer;

  @override
  void dispose() {
    _endedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.callState;

    if (c != null) {
      _wasActive = true;
      _endedMessage = null;
      return const CallScreen();
    }

    // 通话从"有"变"无"的一帧：消费一次结束原因
    if (_wasActive) {
      _wasActive = false;
      final msg = s.callFeedback;
      if (msg.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<AppState>().clearCallFeedback();
          _endedTimer?.cancel();
          setState(() => _endedMessage = msg);
          _endedTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _endedMessage = null);
          });
        });
      }
    }

    final ended = _endedMessage;
    if (ended != null) {
      return Material(
        color: const Color(0xE61B1B22),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(ended,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
