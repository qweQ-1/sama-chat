import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/models.dart';

void main() {
  test('StickerPack JSON 往返', () {
    final p = StickerPack(
      id: 'pk_1',
      name: '小狗表情',
      authorId: 'u_1',
      authorName: '小狗',
      stickers: ['/uploads/a.webp', '/uploads/b.gif'],
      downloads: 3,
      downloaded: true,
      createdAt: 123,
    );
    final q = StickerPack.fromJson(p.toJson());
    expect(q.id, 'pk_1');
    expect(q.name, '小狗表情');
    expect(q.authorId, 'u_1');
    expect(q.stickers.length, 2);
    expect(q.stickers[1], '/uploads/b.gif');
    expect(q.downloads, 3);
    expect(q.downloaded, true);
  });

  test('StickerPack 缺省字段容错', () {
    final q = StickerPack.fromJson({'id': 'x', 'name': 'n'});
    expect(q.stickers, isEmpty);
    expect(q.downloads, 0);
    expect(q.downloaded, false);
    expect(q.authorId, '');
  });

  test('GIF 文件扩展名可识别', () {
    final p = StickerPack(
      id: 'pk_2',
      name: 'gif包',
      stickers: ['/uploads/x.gif'],
    );
    expect(p.stickers.first.endsWith('.gif'), true);
  });
}
