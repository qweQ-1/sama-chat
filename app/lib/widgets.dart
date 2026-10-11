/// Small shared UI pieces.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'store.dart';

/// Deterministic pastel color from any string seed.
Color colorFor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0xffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.50, 0.52).toColor();
}

/// Resolve a possibly-relative image URL against the configured server.
String resolveUrl(BuildContext context, String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = context.read<AppState>().serverBase;
  return '$base$url';
}

/// 全 App 图片磁盘缓存（桌面端也用 JSON 索引，无需 sqlite 插件）。
final CacheManager imageCacheManager = CacheManager(
  Config(
    'samaImages',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 800,
    repo: JsonCacheInfoRepository(databaseName: 'samaImages'),
    fileSystem: IOFileSystem('samaImages'),
  ),
);

/// 带磁盘缓存的网络图片：看过的图第二次打开直接本地秒出，不再走网络。
class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? errorBuilder;
  final Widget? placeholder;

  const NetImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: resolveUrl(context, url),
      cacheManager: imageCacheManager,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, _) =>
          placeholder ??
          Container(
            width: width,
            height: height,
            color: Colors.black.withValues(alpha: 0.05),
          ),
      errorWidget: (context, _, __) =>
          errorBuilder?.call(context) ??
          Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;

  const Avatar({super.key, required this.name, this.url, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final u = url;
    final hasImage = u != null && u.isNotEmpty;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorFor(name),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        name.isNotEmpty ? name.characters.first : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (!hasImage) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: NetImage(
        url: u,
        width: size,
        height: size,
        errorBuilder: (_) => fallback,
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyHint({super.key, required this.text, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }
}

/// Full-screen image viewer (tap image to open).
class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String? heroTag;
  const ImageViewerScreen({super.key, required this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final img = InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: NetImage(
          url: url,
          fit: BoxFit.contain,
          placeholder: const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: heroTag != null ? Hero(tag: heroTag!, child: img) : img,
    );
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
  ));
}

/// 显示未读公告（同一条只弹一次；关闭后立即标记已读）。
/// 在主页 shell 的 build 里调用即可（内部有防重入与空判断）。
void maybeShowAnnouncements(BuildContext context) {
  final s = context.read<AppState>();
  if (s.pendingAnnouncements.isEmpty || s.announcementShown) return;
  s.announcementShown = true;
  final anns = List<Announcement>.of(s.pendingAnnouncements);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) {
      s.announcementShown = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.campaign_outlined, size: 22),
          SizedBox(width: 8),
          Text('公告'),
        ]),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < anns.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  Text(anns[i].content,
                      style: const TextStyle(fontSize: 14.5, height: 1.55)),
                  const SizedBox(height: 6),
                  Text(
                    '—— ${anns[i].authorName} · ${formatTime(anns[i].createdAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
    s.announcementShown = false;
    await s.ackAnnouncements();
  });
}

String previewOf(Message? m, String? myId) {
  if (m == null) return '';
  final who = (myId != null && m.senderId == myId) ? '我: ' : '';
  if (m.recalled) return '$who[已撤回]';
  if (m.isSticker) return '$who[表情]';
  if (m.isImage) return '$who[图片]';
  if (m.isVideo) return '$who[视频]';
  if (m.isVoice) return '$who[语音]';
  if (m.isFile) return '$who[文件] ${m.fileName}';
  return '$who${m.content}';
}

// ============================================================ mama秀
/// mama秀 虚拟形象：纯 Canvas 绘制的卡通小人（全平台一致、无需素材）。
/// [size] 为正方形边长；[ring] = true 时裁成圆形（头像场景）。
class MamaAvatar extends StatelessWidget {
  final MamaShowConfig config;
  final double size;
  final bool ring;

  const MamaAvatar({
    super.key,
    required this.config,
    this.size = 44,
    this.ring = true,
  });

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _MamaPainter(config),
    );
    return RepaintBoundary(
      child: ring
          ? ClipOval(child: SizedBox.square(dimension: size, child: painter))
          : SizedBox.square(dimension: size, child: painter),
    );
  }
}

class _MamaPainter extends CustomPainter {
  final MamaShowConfig c;
  _MamaPainter(this.c);

  static const _skinColors = [
    Color(0xFFFFE3CF),
    Color(0xFFF3C9A4),
    Color(0xFFDCA26F),
    Color(0xFFAE7449),
    Color(0xFF82552F),
  ];
  static const _hairColors = [
    Color(0xFF2E2A33),
    Color(0xFF6D4A2F),
    Color(0xFFE8C04E),
    Color(0xFFC94B3C),
    Color(0xFF4A6FBF),
    Color(0xFFE88BB5),
  ];
  static const _outfitColors = [
    Color(0xFFFFFFFF),
    Color(0xFF33333D),
    Color(0xFFE8574A),
    Color(0xFF4A7DE8),
    Color(0xFF43A867),
    Color(0xFFF2C14E),
  ];
  static const _bgColors = [
    Color(0xFFDCE8FF),
    Color(0xFFFFE1EC),
    Color(0xFFD8F3E3),
    Color(0xFFFFF0D1),
    Color(0xFFE9E1FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 100, 100));

    final skin = _skinColors[c.skin.clamp(0, 4)];
    final hair = _hairColors[c.hairColor.clamp(0, 5)];
    final cloth = _outfitColors[c.outfitColor.clamp(0, 5)];

    // ---------- 背景 ----------
    if (c.bg > 0) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = _bgColors[(c.bg - 1).clamp(0, 4)],
      );
    } else {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = const Color(0xFFF2F2F7));
    }

    // ---------- 头发（后层）----------
    final hairPaint = Paint()..color = hair;
    switch (c.hair) {
      case 3: // 双马尾（后层球）
        canvas.drawCircle(const Offset(18, 50), 10, hairPaint);
        canvas.drawCircle(const Offset(82, 50), 10, hairPaint);
      case 5: // 爆炸头（后层大圆）
        canvas.drawCircle(const Offset(50, 44), 33, hairPaint);
      case 6: // 长直发（后层长条）
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(21, 40, 58, 48), const Radius.circular(16)),
          hairPaint,
        );
      case 7: // 丸子头（后层丸子）
        canvas.drawCircle(const Offset(50, 19), 10, hairPaint);
    }

    // ---------- 身体 ----------
    final bodyPaint = Paint()..color = cloth;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 95), width: 66, height: 48),
      bodyPaint,
    );

    // 衣服细节
    final darkLine = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    switch (c.outfit) {
      case 1: // 连帽衫：拉绳 + 兜帽边缘
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(50, 50), radius: 32),
          0.15 * 3.14159,
          0.7 * 3.14159,
          false,
          Paint()
            ..color = cloth
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
        final rope = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(46, 78), const Offset(45, 90), rope);
        canvas.drawLine(const Offset(54, 78), const Offset(55, 90), rope);
      case 2: // 衬衫：白领
        final collar = Paint()..color = const Color(0xFFF5F5F7);
        final p1 = Path()
          ..moveTo(41, 74)
          ..lineTo(50, 84)
          ..lineTo(46, 74)
          ..close();
        final p2 = Path()
          ..moveTo(59, 74)
          ..lineTo(50, 84)
          ..lineTo(54, 74)
          ..close();
        canvas.drawPath(p1, collar);
        canvas.drawPath(p2, collar);
      case 3: // 裙子：下摆 + 褶线
        final skirt = Path()
          ..moveTo(32, 78)
          ..lineTo(22, 98)
          ..lineTo(78, 98)
          ..lineTo(68, 78)
          ..close();
        canvas.drawPath(skirt, bodyPaint);
        canvas.drawLine(const Offset(40, 82), const Offset(34, 97), darkLine);
        canvas.drawLine(const Offset(50, 82), const Offset(50, 98), darkLine);
        canvas.drawLine(const Offset(60, 82), const Offset(66, 97), darkLine);
      case 4: // 西装：翻领 + 领带
        final lapel = Paint()..color = const Color(0x22000000);
        final l1 = Path()
          ..moveTo(40, 74)
          ..lineTo(50, 90)
          ..lineTo(44, 74)
          ..close();
        final l2 = Path()
          ..moveTo(60, 74)
          ..lineTo(50, 90)
          ..lineTo(56, 74)
          ..close();
        canvas.drawPath(l1, lapel);
        canvas.drawPath(l2, lapel);
        final tie = Path()
          ..moveTo(48, 78)
          ..lineTo(52, 78)
          ..lineTo(54, 92)
          ..lineTo(50, 96)
          ..lineTo(46, 92)
          ..close();
        canvas.drawPath(tie, Paint()..color = const Color(0xFFC94B3C));
      case 5: // 条纹衫
        canvas.save();
        canvas.clipPath(Path()
          ..addOval(Rect.fromCenter(
              center: const Offset(50, 95), width: 66, height: 48)));
        final stripe = Paint()..color = const Color(0x55FFFFFF);
        for (var y = 76.0; y < 100; y += 9) {
          canvas.drawRect(Rect.fromLTWH(0, y, 100, 4), stripe);
        }
        canvas.restore();
    }

    // ---------- 头 ----------
    final skinPaint = Paint()..color = skin;
    canvas.drawCircle(const Offset(25.5, 50), 5, skinPaint);
    canvas.drawCircle(const Offset(74.5, 50), 5, skinPaint);
    canvas.drawCircle(const Offset(50, 47), 25, skinPaint);

    // ---------- 头发（前层：盖头顶）----------
    if (c.hair > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(50, 45), radius: 26.5),
        3.14159, // π：上半圆
        3.14159,
        true,
        hairPaint,
      );
      switch (c.hair) {
        case 1: // 短发：两侧小鬓角
          canvas.drawCircle(const Offset(26, 45), 7, hairPaint);
          canvas.drawCircle(const Offset(74, 45), 7, hairPaint);
        case 2: // 中分：两侧垂发
          canvas.drawOval(
              const Rect.fromLTWH(20, 42, 11, 26), hairPaint);
          canvas.drawOval(
              const Rect.fromLTWH(69, 42, 11, 26), hairPaint);
        case 4: // 呆毛
          canvas.drawCircle(const Offset(26, 45), 7, hairPaint);
          canvas.drawCircle(const Offset(74, 45), 7, hairPaint);
          final ahoge = Paint()
            ..color = hair
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4
            ..strokeCap = StrokeCap.round;
          final path = Path()
            ..moveTo(53, 21)
            ..quadraticBezierTo(62, 10, 55, 5);
          canvas.drawPath(path, ahoge);
      }
    }

    // ---------- 五官 ----------
    final eyePaint = Paint()..color = const Color(0xFF2B2B33);
    canvas.drawCircle(const Offset(41, 49), 3.4, eyePaint);
    canvas.drawCircle(const Offset(59, 49), 3.4, eyePaint);
    final glint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(const Offset(40.2, 47.8), 1.1, glint);
    canvas.drawCircle(const Offset(58.2, 47.8), 1.1, glint);
    // 腮红
    final blush = Paint()..color = const Color(0x33FF8FAB);
    canvas.drawCircle(const Offset(32, 57), 4.4, blush);
    canvas.drawCircle(const Offset(68, 57), 4.4, blush);
    // 嘴
    final mouth = Paint()
      ..color = const Color(0xFF9A5B4F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(46, 57, 8, 5),
      0.15 * 3.14159,
      0.7 * 3.14159,
      false,
      mouth,
    );

    // ---------- 配饰 ----------
    switch (c.acc) {
      case 1: // 圆框眼镜
        final frame = Paint()
          ..color = const Color(0xFF4A4A55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        canvas.drawCircle(const Offset(41, 49), 6.6, frame);
        canvas.drawCircle(const Offset(59, 49), 6.6, frame);
        canvas.drawLine(const Offset(47.6, 49), const Offset(52.4, 49), frame);
      case 2: // 墨镜
        final shade = Paint()..color = const Color(0xFF23232B);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(33, 44.5, 16, 9), const Radius.circular(3.5)),
          shade,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(51, 44.5, 16, 9), const Radius.circular(3.5)),
          shade,
        );
        canvas.drawRect(const Rect.fromLTWH(48.4, 47, 3.2, 2), shade);
      case 3: // 耳机
        final band = Paint()
          ..color = const Color(0xFF4A4A55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6;
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(50, 45), radius: 29),
          3.5,
          2.4,
          false,
          band,
        );
        final cup = Paint()..color = const Color(0xFF4A4A55);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(16.5, 44, 8, 14), const Radius.circular(4)),
          cup,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(75.5, 44, 8, 14), const Radius.circular(4)),
          cup,
        );
      case 4: // 猫耳
        final earL = Path()
          ..moveTo(33, 27)
          ..lineTo(39, 11)
          ..lineTo(46, 23)
          ..close();
        final earR = Path()
          ..moveTo(54, 23)
          ..lineTo(61, 11)
          ..lineTo(67, 27)
          ..close();
        canvas.drawPath(earL, hairPaint);
        canvas.drawPath(earR, hairPaint);
        final inner = Paint()..color = const Color(0xFFFFB6C9);
        final inL = Path()
          ..moveTo(37, 25)
          ..lineTo(39.5, 16)
          ..lineTo(43, 23)
          ..close();
        final inR = Path()
          ..moveTo(57, 23)
          ..lineTo(60.5, 16)
          ..lineTo(63, 25)
          ..close();
        canvas.drawPath(inL, inner);
        canvas.drawPath(inR, inner);
      case 5: // 蝴蝶结
        final bow = Paint()..color = const Color(0xFFFF6F91);
        canvas.drawOval(const Rect.fromLTWH(61, 21, 10, 8), bow);
        canvas.drawOval(const Rect.fromLTWH(71, 21, 10, 8), bow);
        canvas.drawCircle(const Offset(71, 25), 3.2, bow);
      case 6: // 口罩
        final mask = Paint()..color = const Color(0xFFE8F1FF);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(33, 54, 34, 17), const Radius.circular(8)),
          mask,
        );
        final maskLine = Paint()
          ..color = const Color(0x33000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawLine(
            const Offset(35, 58), const Offset(65, 58), maskLine);
        canvas.drawLine(
            const Offset(24, 51), const Offset(35, 57), maskLine);
        canvas.drawLine(
            const Offset(76, 51), const Offset(65, 57), maskLine);
    }
  }

  @override
  bool shouldRepaint(_MamaPainter old) =>
      old.c.skin != c.skin ||
      old.c.hair != c.hair ||
      old.c.hairColor != c.hairColor ||
      old.c.outfit != c.outfit ||
      old.c.outfitColor != c.outfitColor ||
      old.c.acc != c.acc ||
      old.c.bg != c.bg;
}
