/// 语音消息气泡：点按播放 / 停止，显示时长与播放状态。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'widgets.dart';

class VoiceBubble extends StatefulWidget {
  final String url;
  final int duration; // 秒
  final bool isMine;

  const VoiceBubble({
    super.key,
    required this.url,
    required this.duration,
    required this.isMine,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player?.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      final p = _player ??= AudioPlayer();
      final full = resolveUrl(context, widget.url);
      await p.setUrl(full);
      if (mounted) setState(() => _playing = true);
      await p.play();
      if (mounted) setState(() => _playing = false);
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        showError(context, '语音播放失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = widget.isMine ? Colors.white : scheme.onSurface;
    final secs = widget.duration > 0 ? widget.duration : 0;
    // 气泡宽度随时长变长（微信风格）
    final width = (90 + secs.clamp(1, 60) * 1.6).toDouble();
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: widget.isMine
              ? scheme.primary
              : (Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : scheme.surfaceContainerHighest),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMine ? 16 : 4),
            bottomRight: Radius.circular(widget.isMine ? 4 : 16),
          ),
          boxShadow: widget.isMine
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4)
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              color: fg,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _playing ? '播放中…' : '$secs"',
                  style: TextStyle(color: fg, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
