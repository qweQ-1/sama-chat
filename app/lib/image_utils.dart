/// 图片上传前的压缩/瘦身：统一转 WebP + 限制长边。
/// 服务端原生支持 webp 格式，无需改动——体积通常能小 3~5 倍，
/// 上传下载都快得多。桌面端插件不可用时会自动退回原图，不影响发送。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// 压缩结果：压缩后的字节 + 对应扩展名。
typedef CompressedImage = ({Uint8List bytes, String ext});

/// 上传前压缩：长边封顶 [maxDim]（默认 1280），质量 [quality]（默认 78）。
/// 优先 WebP；凡是失败都会逐级回退（WebP → JPEG → 原图），不影响发送。
Future<CompressedImage> compressImage(
  Uint8List bytes, {
  int maxDim = 1280,
  int quality = 78,
  String fallbackExt = 'jpg',
}) async {
  try {
    final webp = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxDim,
      minHeight: maxDim,
      quality: quality,
      format: CompressFormat.webp,
    );
    if (webp.isNotEmpty && webp.length < bytes.length) {
      return (bytes: webp, ext: 'webp');
    }
  } catch (_) {}

  try {
    final jpg = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxDim,
      minHeight: maxDim,
      quality: quality,
      format: CompressFormat.jpeg,
    );
    if (jpg.isNotEmpty && jpg.length < bytes.length) {
      return (bytes: jpg, ext: 'jpg');
    }
  } catch (_) {}

  // 压缩不可用（桌面端）或没变小：用原图
  return (bytes: bytes, ext: fallbackExt);
}

/// 生成「表情包」专用小图：长边封顶 [maxDim]（默认 240）。
/// 优先 WebP（移动端体积小）；失败时用纯 Flutter 缩放成 PNG（桌面端也有效）；
/// 再不济回退原图，保证一定能导入。
Future<CompressedImage> makeSticker(
  Uint8List bytes, {
  int maxDim = 240,
  String fallbackExt = 'png',
}) async {
  try {
    final webp = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxDim,
      minHeight: maxDim,
      quality: 82,
      format: CompressFormat.webp,
    );
    if (webp.isNotEmpty && webp.length < bytes.length) {
      return (bytes: webp, ext: 'webp');
    }
  } catch (_) {}

  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final longSide = math.max(img.width, img.height);
    final scale = longSide > maxDim ? maxDim / longSide : 1.0;
    final w = math.max(1, (img.width * scale).round());
    final h = math.max(1, (img.height * scale).round());
    var out = img;
    if (w != img.width || h != img.height) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      out = await recorder.endRecording().toImage(w, h);
    }
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    if (data != null && data.lengthInBytes > 0) {
      return (bytes: data.buffer.asUint8List(), ext: 'png');
    }
  } catch (_) {}

  return (bytes: bytes, ext: fallbackExt);
}
