import 'package:flutter_test/flutter_test.dart';
import 'package:samachat/models.dart';

void main() {
  group('User', () {
    test('parses full json', () {
      final u = User.fromJson({
        'id': 'u_1',
        'username': 'alice',
        'displayName': '爱丽丝',
        'avatar': '/uploads/img_x.png',
        'createdAt': 123,
      });
      expect(u.id, 'u_1');
      expect(u.displayName, '爱丽丝');
      expect(u.avatar, '/uploads/img_x.png');
    });

    test('falls back displayName to username', () {
      final u = User.fromJson({'id': 'u_2', 'username': 'bob'});
      expect(u.displayName, 'bob');
      expect(u.avatar, isNull);
    });
  });

  group('Message', () {
    test('parses text message', () {
      final m = Message.fromJson({
        'id': 'm_1',
        'conversationId': 'cv_1',
        'senderId': 'u_1',
        'type': 'text',
        'content': '你好',
        'createdAt': 1000,
        'readBy': ['u_1'],
        'sender': {'id': 'u_1', 'username': 'alice', 'displayName': '爱丽丝'},
      });
      expect(m.isImage, false);
      expect(m.content, '你好');
      expect(m.readBy, ['u_1']);
      expect(m.sender?.displayName, '爱丽丝');
    });

    test('parses image message', () {
      final m = Message.fromJson({
        'id': 'm_2',
        'conversationId': 'cv_1',
        'senderId': 'u_1',
        'type': 'image',
        'content': '/uploads/img_a.jpg',
        'createdAt': 1001,
      });
      expect(m.isImage, true);
      expect(m.readBy, isEmpty);
    });
  });

  group('Conversation', () {
    test('parses group with last message', () {
      final c = Conversation.fromJson({
        'id': 'cv_9',
        'type': 'group',
        'name': '测试群',
        'memberIds': ['a', 'b', 'c'],
        'memberCount': 3,
        'unread': 2,
        'lastMessage': {
          'id': 'm_9',
          'conversationId': 'cv_9',
          'senderId': 'b',
          'type': 'text',
          'content': 'hi',
          'createdAt': 5,
          'readBy': [],
        },
      });
      expect(c.isGroup, true);
      expect(c.unread, 2);
      expect(c.lastMessage?.content, 'hi');
    });
  });

  group('Moment', () {
    test('parses likes and comments', () {
      final m = Moment.fromJson({
        'id': 'mo_1',
        'authorId': 'u_1',
        'text': '今天天气真好',
        'images': ['/uploads/a.jpg', '/uploads/b.jpg'],
        'createdAt': 42,
        'likes': ['u_2', 'u_3'],
        'likeCount': 2,
        'likedByMe': true,
        'comments': [
          {
            'id': 'cm_1',
            'authorId': 'u_2',
            'author': {'id': 'u_2', 'username': 'bob', 'displayName': '鲍勃'},
            'text': '确实',
            'createdAt': 43,
          }
        ],
        'author': {'id': 'u_1', 'username': 'alice', 'displayName': '爱丽丝'},
      });
      expect(m.text, '今天天气真好');
      expect(m.images.length, 2);
      expect(m.likeCount, 2);
      expect(m.likedByMe, true);
      expect(m.comments.single.text, '确实');
      expect(m.author?.displayName, '爱丽丝');
    });

    test('falls back likeCount from likes array', () {
      final m = Moment.fromJson({
        'id': 'mo_2',
        'text': 'x',
        'images': [],
        'createdAt': 1,
        'likes': ['a'],
        'comments': [],
      });
      expect(m.likeCount, 1);
      expect(m.likedByMe, false);
    });
  });

  group('parseAddPayload', () {
    test('parses samachat:// payload', () {
      expect(parseAddPayload('samachat://add?uid=u_abc123'), 'u_abc123');
    });
    test('accepts bare uid', () {
      expect(parseAddPayload('u_abc123'), 'u_abc123');
    });
    test('rejects junk', () {
      expect(parseAddPayload('https://example.com/page'), isNull);
      expect(parseAddPayload(''), isNull);
      expect(parseAddPayload(null), isNull);
      expect(parseAddPayload('random text'), isNull);
    });
  });

  group('time formatting', () {
    test('just now', () {
      expect(formatTime(DateTime.now().millisecondsSinceEpoch), '刚刚');
    });
    test('empty for zero', () {
      expect(formatTime(0), '');
    });
    test('minutes ago', () {
      final t = DateTime.now().subtract(const Duration(minutes: 5));
      expect(formatTime(t.millisecondsSinceEpoch), '5 分钟前');
    });
    test('older than a day shows date', () {
      final t = DateTime.now().subtract(const Duration(days: 3));
      final s = formatTime(t.millisecondsSinceEpoch);
      expect(s.contains(':'), true); // has time part
    });
  });

  group('FriendRequest', () {
    test('parses with nested user', () {
      final r = FriendRequest.fromJson({
        'id': 'fq_1',
        'fromId': 'u_1',
        'toId': 'u_2',
        'status': 'pending',
        'createdAt': 7,
        'from': {'id': 'u_1', 'username': 'alice', 'displayName': '爱丽丝'},
      });
      expect(r.status, 'pending');
      expect(r.from?.username, 'alice');
    });
  });
}
