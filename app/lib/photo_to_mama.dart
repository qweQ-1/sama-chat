/// 照片 → mama秀：端侧人脸检测 + 颜色分析，自动生成虚拟形象配置。
///
/// 原理（不联网、不上传、零成本）：
/// 1. ML Kit 检测照片中最大的人脸
/// 2. 在脸颊区采平均色 → 映射肤色档位
/// 3. 在头顶区采暗部主色 → 映射发色；并按头发像素分布猜发型
/// 4. 在躯干区采主色 → 映射衣服颜色
///
/// 坐标对齐：ML Kit 的 boundingBox 是「按 EXIF 校正后」的坐标；
/// Flutter 解码（instantiateImageCodec）同样应用 EXIF 方向 → 两套坐标同向，
/// 按 W(原图)→W(缩略) 等比换算即可。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'models.dart';

/// 分析失败（无人脸等）。
class MamaPhotoException implements Exception {
  final String message;
  MamaPhotoException(this.message);
  @override
  String toString() => message;
}

/// 从照片生成 mama秀 配置（调用方负责 try-catch MamaPhotoException）。
Future<MamaShowConfig> generateMamaFromPhoto(String path) async {
  // ---------- 1. 人脸检测 ----------
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );
  List<Face> faces;
  try {
    faces = await detector.processImage(InputImage.fromFilePath(path));
  } finally {
    await detector.close();
  }
  if (faces.isEmpty) {
    throw MamaPhotoException('没检测到人脸，换一张清晰的正脸照试试');
  }
  // 取最大的脸
  final face = faces.reduce((a, b) => a.boundingBox.width * a.boundingBox.height >
          b.boundingBox.width * b.boundingBox.height
      ? a
      : b);
  final box = face.boundingBox;

  // ---------- 2. 解码像素（缩略图）----------
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final w0 = descriptor.width;
  final h0 = descriptor.height;
  if (w0 <= 0 || h0 <= 0) throw MamaPhotoException('图片读取失败');

  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bd == null) throw MamaPhotoException('图片解析失败');
  final px = bd.buffer.asUint8List();
  final w = img.width;
  final h = img.height;
  img.dispose();

  // 原图坐标 → 缩略坐标
  final s = w / w0;
  final bx = box.left * s;
  final by = box.top * s;
  final bw = box.width * s;
  final bh = box.height * s;

  // ---------- 3. 采样 ----------
  // 脸颊（脸框下部中央）
  final cheek = _avgRegion(
    px, w, h,
    (bx + bw * 0.28).round(), (by + bh * 0.55).round(),
    (bx + bw * 0.72).round(), (by + bh * 0.88).round(),
  );
  final skin = mapSkin(cheek);

  // 头发：头顶区取「暗半段」平均（排除背景与皮肤）
  final hairTop = _avgDarkHalf(
    px, w, h,
    (bx - bw * 0.25).round(), (by - bh * 0.55).round(),
    (bx + bw * 1.25).round(), (by + bh * 0.18).round(),
  );
  final hairColor = mapHair(hairTop);

  // 衣服：躯干区（脸下方）
  var torso = _avgRegion(
    px, w, h,
    (bx + bw * 0.25).round(), (by + bh * 1.5).round(),
    (bx + bw * 0.75).round(), (by + bh * 2.4).round(),
  );
  // 躯干超出图片 → 退化为整图下半部
  if (torso.a == 0) {
    torso = _avgRegion(px, w, h, (w * 0.3).round(), (h * 0.72).round(),
        (w * 0.7).round(), (h * 0.95).round());
  }
  final outfitColor = mapOutfit(torso);

  // 发型：统计与发色相近的像素分布
  final hair = _hairStyle(px, w, h, bx, by, bw, bh, hairTop);

  return MamaShowConfig(
    skin: skin,
    hair: hair,
    hairColor: hairColor,
    outfit: 0,
    outfitColor: outfitColor,
    acc: 0,
    bg: 0,
  );
}

// ============================================================ 颜色工具

/// 区域平均色；全透明像素跳过。返回 a=0 表示区域无效/越界。
Color _avgRegion(Uint8List p, int w, int h, int x0, int y0, int x1, int y1) {
  x0 = x0.clamp(0, w - 1);
  x1 = x1.clamp(0, w - 1);
  y0 = y0.clamp(0, h - 1);
  y1 = y1.clamp(0, h - 1);
  if (x1 <= x0 || y1 <= y0) return const Color(0x00000000);
  var r = 0, g = 0, b = 0, n = 0;
  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      final i = (y * w + x) * 4;
      if (p[i + 3] < 200) continue;
      r += p[i];
      g += p[i + 1];
      b += p[i + 2];
      n++;
    }
  }
  if (n == 0) return const Color(0x00000000);
  return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
}

/// 区域内「较暗的一半」像素平均（用于找头发：头发通常暗于背景）。
Color _avgDarkHalf(Uint8List p, int w, int h, int x0, int y0, int x1, int y1) {
  x0 = x0.clamp(0, w - 1);
  x1 = x1.clamp(0, w - 1);
  y0 = y0.clamp(0, h - 1);
  y1 = y1.clamp(0, h - 1);
  if (x1 <= x0 || y1 <= y0) return const Color(0xFF2E2A33);
  final samples = <(int, int, int, int)>[]; // (lum, r, g, b)
  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      final i = (y * w + x) * 4;
      if (p[i + 3] < 200) continue;
      final lum = (p[i] * 299 + p[i + 1] * 587 + p[i + 2] * 114) ~/ 1000;
      samples.add((lum, p[i], p[i + 1], p[i + 2]));
    }
  }
  if (samples.isEmpty) return const Color(0xFF2E2A33);
  samples.sort((a, b) => a.$1.compareTo(b.$1));
  final take = math.max(1, samples.length ~/ 2);
  var r = 0, g = 0, b = 0;
  for (var i = 0; i < take; i++) {
    r += samples[i].$2;
    g += samples[i].$3;
    b += samples[i].$4;
  }
  return Color.fromARGB(255, r ~/ take, g ~/ take, b ~/ take);
}

/// 与参考色的加权欧氏距离（人眼对绿最敏感，简单加权）。
double _colorDist(Color a, Color b) {
  final dr = (a.r * 255 - b.r * 255);
  final dg = (a.g * 255 - b.g * 255);
  final db = (a.b * 255 - b.b * 255);
  return math.sqrt(dr * dr * 0.9 + dg * dg * 1.2 + db * db * 0.9);
}

// ============================================================ 档位映射

/// 肤色 5 档：按亮度切分（浅 → 深）。
int mapSkin(Color c) {
  final lum = (c.r * 255 * 299 + c.g * 255 * 587 + c.b * 255 * 114) / 1000;
  if (lum > 215) return 0;
  if (lum > 190) return 1;
  if (lum > 160) return 2;
  if (lum > 125) return 3;
  return 4;
}

const _hairRefs = [
  Color(0xFF2E2A33), // 黑
  Color(0xFF6D4A2F), // 棕
  Color(0xFFE8C04E), // 金
  Color(0xFFC94B3C), // 红
  Color(0xFF4A6FBF), // 蓝
  Color(0xFFE88BB5), // 粉
];

/// 发色 6 档：最近参考色。
int mapHair(Color c) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < _hairRefs.length; i++) {
    final d = _colorDist(c, _hairRefs[i]);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// 衣服颜色 6 档：先按饱和度/亮度分白黑，再按色相分彩色。
int mapOutfit(Color c) {
  final r = c.r * 255, g = c.g * 255, b = c.b * 255;
  final maxV = math.max(r, math.max(g, b));
  final minV = math.min(r, math.min(g, b));
  final sat = maxV <= 0 ? 0.0 : (maxV - minV) / maxV;
  if (sat < 0.16) {
    // 灰阶：亮 → 白(0)，暗 → 黑(1)
    return maxV > 140 ? 0 : 1;
  }
  // 色相
  double hue;
  if (maxV == r) {
    hue = 60 * ((g - b) / (maxV - minV));
  } else if (maxV == g) {
    hue = 60 * (2 + (b - r) / (maxV - minV));
  } else {
    hue = 60 * (4 + (r - g) / (maxV - minV));
  }
  if (hue < 0) hue += 360;
  if (hue < 25 || hue >= 330) return 2; // 红
  if (hue < 70) return 5; // 黄
  if (hue < 165) return 4; // 绿
  return 3; // 蓝（含紫）
}

/// 发型启发式：统计「与发色相近」的像素包围盒。
/// - 横向很宽 → 爆炸头(5)
/// - 纵向很长（垂到脸下方） → 长直发(6)
/// - 否则短发(1)
int _hairStyle(Uint8List p, int w, int h, double bx, double by, double bw,
    double bh, Color hairColor) {
  final x0 = (bx - bw * 0.5).round().clamp(0, w - 1);
  final x1 = (bx + bw * 1.5).round().clamp(0, w - 1);
  final y0 = (by - bh * 0.8).round().clamp(0, h - 1);
  final y1 = (by + bh * 1.0).round().clamp(0, h - 1);
  var minX = w, maxX = 0, minY = h, maxY = 0, count = 0;
  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      final i = (y * w + x) * 4;
      if (p[i + 3] < 200) continue;
      final c = Color.fromARGB(255, p[i], p[i + 1], p[i + 2]);
      if (_colorDist(c, hairColor) > 90) continue;
      count++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (count < 12) return 1; // 头发太少 → 默认短发
  final hRatio = (maxY - minY) / math.max(1.0, bh);
  final wRatio = (maxX - minX) / math.max(1.0, bw);
  if (wRatio > 1.9) return 5; // 爆炸头
  if (hRatio > 1.55) return 6; // 长直发
  return 1; // 短发
}
