import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/image_utils.dart';
import 'package:samachat/models.dart';
import 'package:samachat/screens/sticker_panel.dart';

void main() {
  test('Message sticker 类型解析', () {
    final m = Message.fromJson({
      'id': 'm1',
      'conversationId': 'c1',
      'senderId': 'u1',
      'type': 'sticker',
      'content': '/uploads/x.webp',
      'createdAt': 1,
      'readBy': [],
    });
    expect(m.isSticker, true);
    expect(m.isImage, false);
    expect(m.isVideo, false);
  });

  test('普通消息不是 sticker', () {
    final m = Message.fromJson({
      'id': 'm2',
      'conversationId': 'c1',
      'senderId': 'u1',
      'type': 'text',
      'content': 'hi',
      'createdAt': 1,
      'readBy': [],
    });
    expect(m.isSticker, false);
  });

  test('内置表情列表充足', () {
    expect(kBuiltinEmojis.length, greaterThan(80));
  });

  test('makeSticker 全部失败时回退原图', () async {
    final raw = Uint8List.fromList([1, 2, 3, 4]);
    final r = await makeSticker(raw, fallbackExt: 'png');
    expect(r.bytes, raw);
    expect(r.ext, 'png');
  });
}
