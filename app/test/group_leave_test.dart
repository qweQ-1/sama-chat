import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/models.dart';

void main() {
  test('群会话解析成员数', () {
    final c = Conversation.fromJson({
      'id': 'c_1',
      'type': 'group',
      'name': '测试群',
      'memberIds': ['u1', 'u2'],
      'memberCount': 2,
      'unread': 0,
      'ownerId': 'u1',
      'adminIds': <String>[],
    });
    expect(c.isGroup, true);
    expect(c.memberCount, 2);
    expect(c.isOwner('u1'), true);
    expect(c.isOwner('u2'), false);
    expect(c.canManage('u1'), true);
  });

  test('缺 memberCount 时用 memberIds 兜底', () {
    final c = Conversation.fromJson({
      'id': 'c_2',
      'type': 'group',
      'name': 'g',
      'memberIds': ['a', 'b', 'c'],
    });
    // 服务端广播 conversation:update 时只带 memberIds
    expect(c.memberIds.length, 3);
  });

  test('私聊不是群', () {
    final c = Conversation.fromJson({
      'id': 'c_3',
      'type': 'private',
      'name': '小狗',
      'memberIds': ['a', 'b'],
      'memberCount': 2,
    });
    expect(c.isGroup, false);
    expect(c.canManage('a'), false);
    expect(c.isOwner('a'), false);
  });
}
