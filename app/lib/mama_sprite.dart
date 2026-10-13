/// mama秀 立绘（AI 全身形象）展示组件 + 代码驱动的动作动画。
///
/// 动作方案（无需多帧图片，一张透明底立绘即可）：
/// - idle   呼吸起伏 + 轻微上下浮动（常驻，像活着一样）
/// - bounce 发消息时向上弹跳一下
/// - shake  收到消息时轻微左右摇摆
/// - spin   点击时转个圈（互动彩蛋）
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets.dart';

/// 动作类型。
enum MamaMove { idle, bounce, shake, spin }

/// 立绘展示：支持动作动画。
///
/// [url] 立绘图片地址（相对路径会自动补全服务器前缀）。
/// [height] 展示高度（宽度按图片比例自适应）。
/// [move] 当前动作；[moveKey] 变化时重新触发该动作。
class MamaSprite extends StatefulWidget {
  final String url;
  final double height;
  final MamaMove move;
  final int moveKey;
  final VoidCallback? onTap;

  const MamaSprite({
    super.key,
    required this.url,
    this.height = 110,
    this.move = MamaMove.idle,
    this.moveKey = 0,
    this.onTap,
  });

  @override
  State<MamaSprite> createState() => _MamaSpriteState();
}

class _MamaSpriteState extends State<MamaSprite>
    with TickerProviderStateMixin {
  /// 常驻待机动画（呼吸 + 浮动）
  late final AnimationController _idle;

  /// 一次性动作动画
  late final AnimationController _action;

  MamaMove _activeMove = MamaMove.idle;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _action = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _action.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _activeMove = MamaMove.idle);
      }
    });
  }

  @override
  void didUpdateWidget(MamaSprite old) {
    super.didUpdateWidget(old);
    if (old.moveKey != widget.moveKey && widget.move != MamaMove.idle) {
      _playAction(widget.move);
    }
  }

  void _playAction(MamaMove move) {
    setState(() => _activeMove = move);
    _action.duration = Duration(milliseconds: move == MamaMove.spin ? 900 : 620);
    _action.forward(from: 0);
  }

  @override
  void dispose() {
    _idle.dispose();
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = resolveUrl(context, widget.url);

    return GestureDetector(
      onTap: widget.onTap ?? () => _playAction(MamaMove.spin),
      child: AnimatedBuilder(
        animation: Listenable.merge([_idle, _action]),
        builder: (context, _) {
          final t = _action.value;
          // 待机：上下浮动 ±1.5% + 纵向轻微呼吸缩放
          final idleFloat = (_idle.value - 0.5) * 2; // -1..1
          double dy = idleFloat * widget.height * 0.015;
          double scaleY = 1 + idleFloat * 0.008;
          double scaleX = 1 - idleFloat * 0.004;
          double angle = 0;

          switch (_activeMove) {
            case MamaMove.bounce:
              // 先向上再回落，用 sin 曲线更自然
              final p = math.sin(t * math.pi);
              dy -= p * widget.height * 0.09;
              scaleY += p * 0.03;
              scaleX -= p * 0.03;
            case MamaMove.shake:
              final p = math.sin(t * math.pi * 3) * (1 - t);
              angle = p * 0.10;
            case MamaMove.spin:
              // 转一圈（绕 Y 轴缩放模拟 3D 旋转）
              final p = t;
              scaleX *= (1 - 2 * (p < 0.5 ? p : 1 - p) * 0.85).abs().clamp(0.15, 1.0);
              dy -= math.sin(t * math.pi) * widget.height * 0.05;
            case MamaMove.idle:
              break;
          }

          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                child: Opacity(
                  opacity: 0.98,
                  child: NetImage(
                    url: widget.url,
                    height: widget.height,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
