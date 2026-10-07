import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/models.dart';

void main() {
  group('v2.2.0 新消息类型', () {
    test('语音消息解析（duration）', () {
      final m = Message.fromJson({
        'id': 'm1',
        'conversationId': 'c1',
        'senderId': 'u1',
        'type': 'voice',
        'content': '/uploads/v.m4a',
        'duration': 12,
        'createdAt': 1,
        'readBy': [],
      });
      expect(m.isVoice, true);
      expect(m.duration, 12);
      expect(m.isText, false);
    });

    test('文件消息解析（fileName/fileSize）', () {
      final m = Message.fromJson({
        'id': 'm2',
        'conversationId': 'c1',
        'senderId': 'u1',
        'type': 'file',
        'content': '/uploads/f.pdf',
        'fileName': '报告.pdf',
        'fileSize': 2048,
        'createdAt': 1,
        'readBy': [],
      });
      expect(m.isFile, true);
      expect(m.fileName, '报告.pdf');
      expect(m.fileSize, 2048);
    });

    test('回复消息解析（replyToId/replyPreview）', () {
      final m = Message.fromJson({
        'id': 'm3',
        'conversationId': 'c1',
        'senderId': 'u1',
        'type': 'text',
        'content': '回复内容',
        'replyToId': 'm0',
        'replyPreview': '小狗: 原消息',
        'createdAt': 1,
        'readBy': [],
      });
      expect(m.replyToId, 'm0');
      expect(m.replyPreview, '小狗: 原消息');
    });

    test('copyWith 保留回复字段', () {
      final m = Message(
        id: 'm4',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        content: 'x',
        createdAt: 1,
        readBy: const [],
        replyToId: 'm0',
        replyPreview: 'p',
        duration: 5,
        fileName: 'a.txt',
        fileSize: 100,
      );
      final c = m.copyWith(pending: true);
      expect(c.replyToId, 'm0');
      expect(c.duration, 5);
      expect(c.fileName, 'a.txt');
      expect(c.pending, true);
    });
  });

  group('置顶 / 免打扰', () {
    test('Conversation pinned/muted 解析', () {
      final c = Conversation.fromJson({
        'id': 'c1',
        'type': 'group',
        'name': '群',
        'memberIds': ['a'],
        'memberCount': 1,
        'pinned': true,
        'muted': true,
      });
      expect(c.pinned, true);
      expect(c.muted, true);
    });

    test('缺省为 false', () {
      final c = Conversation.fromJson({
        'id': 'c1',
        'type': 'private',
        'name': 'p',
        'memberIds': ['a', 'b'],
      });
      expect(c.pinned, false);
      expect(c.muted, false);
    });

    test('copyWith 保留 pinned/muted', () {
      final c = Conversation(
        id: 'c1',
        type: 'private',
        name: 'p',
        memberIds: const ['a', 'b'],
        memberCount: 2,
        pinned: true,
        muted: true,
      );
      final u = c.copyWith(unread: 3);
      expect(u.pinned, true);
      expect(u.muted, true);
      expect(u.unread, 3);
    });
  });

  group('搜索 / 投票', () {
    test('SearchHit 解析', () {
      final h = SearchHit.fromJson({
        'id': 'm1',
        'conversationId': 'c1',
        'conversationName': '小狗',
        'isGroup': false,
        'senderName': '爱丽丝',
        'content': 'hello world',
        'createdAt': 123,
      });
      expect(h.conversationName, '小狗');
      expect(h.content, 'hello world');
    });

    test('Poll 解析（含选项票数）', () {
      final p = Poll.fromJson({
        'id': 'p1',
        'conversationId': 'c1',
        'creatorId': 'u1',
        'creatorName': '小狗',
        'question': '今晚吃啥',
        'options': [
          {'id': 'o1', 'text': '火锅', 'count': 2, 'votedByMe': true},
          {'id': 'o2', 'text': '烧烤', 'count': 1, 'votedByMe': false},
        ],
        'totalVotes': 3,
        'closed': false,
        'createdAt': 1,
      });
      expect(p.options.length, 2);
      expect(p.options[0].votedByMe, true);
      expect(p.totalVotes, 3);
      expect(p.closed, false);
    });
  });
}
