import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/image_utils.dart';

/// GIF magic bytes（GIF89a / GIF87a）
final _gif89a = Uint8List.fromList([
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
  0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
]);
final _gif87a = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0x00, 0x00]);

/// 普通 PNG 头
final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

/// 普通 JPEG 头
final _jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);

void main() {
  group('GIF 动图识别（防止被压缩成静态图）', () {
    test('识别 GIF89a 字节头', () {
      expect(isGifBytes(_gif89a), true);
    });

    test('识别 GIF87a 字节头', () {
      expect(isGifBytes(_gif87a), true);
    });

    test('普通图片不是 GIF', () {
      expect(isGifBytes(_png), false);
      expect(isGifBytes(_jpg), false);
    });

    test('太短的字节不是 GIF', () {
      expect(isGifBytes(Uint8List.fromList([0x47, 0x49])), false);
    });

    test('字节头优先：后缀名骗不了它', () {
      // 相册里常见的坑：后缀是 .jpg 但内容是 GIF
      expect(isAnimatedGif(_gif89a, 'jpg'), true);
      // 反过来：后缀 .gif 但内容不是（也按 GIF 处理，宁可原样上传）
      expect(isAnimatedGif(_png, 'gif'), true);
    });

    test('普通图片 + 普通后缀 → 可以走压缩', () {
      expect(isAnimatedGif(_png, 'png'), false);
      expect(isAnimatedGif(_jpg, 'JPG'), false); // 大小写不敏感
      expect(isAnimatedGif(_png, 'PNG'), false);
    });
  });
}
