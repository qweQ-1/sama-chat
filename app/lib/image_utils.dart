/// 图片上传前的压缩/瘦身：统一转 WebP + 限制长边。
/// 服务端原生支持 webp 格式，无需改动——体积通常能小 3~5 倍，
/// 上传下载都快得多。桌面端插件不可用时会自动退回原图，不影响发送。
library;

import 'dart:typed_data';

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
