/// mama秀 立绘播放器：AI 生成的动作帧序列播放 + 待机循环。
///
/// 动作由 AI 生成的多帧图片组成（透明底），本组件负责：
/// - idle：显示待机立绘（静态/轻微呼吸）
/// - wave：PingPong 循环播放动作帧（1→2→3→2→1…），自然顺滑
/// - 播放完指定轮次后自动回到待机
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets.dart';

/// 立绘动作类型。
enum SpriteAction { idle, wave }

/// mama秀 立绘：静态待机 + AI 动作帧播放。
class MamaSprite extends StatefulWidget {
  /// 待机立绘地址。
  final String url;

  /// 动作帧地址列表（PingPong 顺序播放）。
  final List<String> frames;

  final double height;

  /// 当前动作。
  final SpriteAction action;

  /// 变化时重新触发动作（配合 [action] 使用）。
  final int actionKey;

  /// 动作播完一轮后自动回到待机（回调通知父组件）。
  final VoidCallback? onActionDone;

  final VoidCallback? onTap;

  const MamaSprite({
    super.key,
    required this.url,
    this.frames = const [],
    this.height = 110,
    this.action = SpriteAction.idle,
    this.actionKey = 0,
    this.onActionDone,
    this.onTap,
  });

  @override
  State<MamaSprite> createState() => _MamaSpriteState();
}

class _MamaSpriteState extends State<MamaSprite> {
  /// 当前显示的动作帧索引（-1 = 待机图）
  int _frameIdx = -1;
  Timer? _timer;

  /// PingPong 播放序列：0,1,2,1 循环
  List<int> _seq = const [];
  int _seqPos = 0;
  int _cyclesLeft = 0;

  @override
  void initState() {
    super.initState();
    if (widget.action == SpriteAction.wave) _startWave();
  }

  @override
  void didUpdateWidget(MamaSprite old) {
    super.didUpdateWidget(old);
    if (old.actionKey != widget.actionKey) {
      if (widget.action == SpriteAction.wave) {
        _startWave();
      } else {
        _stopAction();
      }
    }
  }

  void _startWave() {
    final n = widget.frames.length;
    if (n == 0) return; // 没有动作帧 → 保持待机
    // PingPong 序列：0→1→…→n-1→…→1，循环播放
    _seq = n == 1 ? [0] : [...List.generate(n, (i) => i), ...List.generate(n - 2, (i) => n - 2 - i)];
    _seqPos = 0;
    _cyclesLeft = 2; // 播放 2 轮
    setState(() => _frameIdx = _seq[0]);
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 340), () {
      if (!mounted) return;
      _seqPos++;
      if (_seqPos >= _seq.length) {
        _seqPos = 0;
        _cyclesLeft--;
        if (_cyclesLeft <= 0) {
          _stopAction();
          widget.onActionDone?.call();
          return;
        }
      }
      setState(() => _frameIdx = _seq[_seqPos]);
      _tick();
    });
  }

  void _stopAction() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _frameIdx = -1);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = _frameIdx >= 0 && _frameIdx < widget.frames.length;
    final src = showing ? widget.frames[_frameIdx] : widget.url;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        // 帧切换用交叉淡化，避免闪烁
        child: NetImage(
          key: ValueKey(src),
          url: src,
          height: widget.height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// 点击即可挥手的小组件：内部维护「点击 → 播一次挥手 → 回待机」的状态。
/// 用于「我」页面、mama秀编辑器、全屏查看等场景。
class TappableSprite extends StatefulWidget {
  final String url;
  final List<String> frames;
  final double height;
  final VoidCallback? onTap;

  const TappableSprite({
    super.key,
    required this.url,
    this.frames = const [],
    this.height = 170,
    this.onTap,
  });

  @override
  State<TappableSprite> createState() => _TappableSpriteState();
}

class _TappableSpriteState extends State<TappableSprite> {
  int _waveKey = 0;
  bool _waving = false;

  void _handleTap() {
    if (widget.frames.isNotEmpty) {
      setState(() {
        _waving = true;
        _waveKey++;
      });
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MamaSprite(
      url: widget.url,
      frames: widget.frames,
      height: widget.height,
      action: _waving ? SpriteAction.wave : SpriteAction.idle,
      actionKey: _waveKey,
      onActionDone: () {
        if (mounted) setState(() => _waving = false);
      },
      onTap: _handleTap,
    );
  }
}
