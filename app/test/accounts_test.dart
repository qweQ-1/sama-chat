import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/models.dart';
import 'package:samachat/store.dart';

void main() {
  test('SavedAccount JSON 往返', () {
    final a = SavedAccount(
      id: 'u_1',
      token: 't_1',
      displayName: '小狗',
      username: 'dog',
      avatar: '/uploads/a.jpg',
      email: 'a@b.com',
      serverBase: 'https://x.dev',
    );
    final b = SavedAccount.fromJson(a.toJson());
    expect(b.id, 'u_1');
    expect(b.token, 't_1');
    expect(b.displayName, '小狗');
    expect(b.username, 'dog');
    expect(b.email, 'a@b.com');
    expect(b.ident, 'a@b.com');
  });

  test('SavedAccount ident 回退（手机号 / 用户名）', () {
    final c = SavedAccount.fromJson(SavedAccount(
      id: 'u_2',
      token: 't_2',
      displayName: 'x',
      username: 'x2',
      phone: '13800000000',
      serverBase: '',
    ).toJson());
    expect(c.ident, '13800000000');
    final d = SavedAccount.fromJson(SavedAccount(
      id: 'u_3',
      token: 't_3',
      displayName: 'y',
      username: 'y3',
      serverBase: '',
    ).toJson());
    expect(d.ident, '@y3');
  });

  test('Announcement 解析', () {
    final a = Announcement.fromJson({
      'id': 'ann_1',
      'content': '你好',
      'authorName': 'huzhi',
      'createdAt': 123,
    });
    expect(a.content, '你好');
    expect(a.authorName, 'huzhi');
    expect(a.createdAt, 123);
  });

  test('User canAnnounce 解析（默认 false）', () {
    final u = User.fromJson({'id': 'u', 'username': 'a', 'displayName': 'A'});
    expect(u.canAnnounce, false);
    final v = User.fromJson({
      'id': 'u2',
      'username': 'huzhi',
      'displayName': 'huzhi',
      'canAnnounce': true,
    });
    expect(v.canAnnounce, true);
  });
}
