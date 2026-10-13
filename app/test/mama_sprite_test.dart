import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/mama_sprite.dart';

void main() {
  group('mama秀 立绘动作（v2.8.0）', () {
    test('动作枚举齐全', () {
      expect(MamaMove.values, contains(MamaMove.idle));
      expect(MamaMove.values, contains(MamaMove.bounce));
      expect(MamaMove.values, contains(MamaMove.shake));
      expect(MamaMove.values, contains(MamaMove.spin));
      expect(MamaMove.values.length, 4);
    });

    test('idle 是默认动作（构造参数）', () {
      const w = MamaSprite(url: '/uploads/mama_x.png');
      expect(w.move, MamaMove.idle);
      expect(w.height, 110);
      expect(w.moveKey, 0);
    });

    test('可指定动作与尺寸', () {
      const w = MamaSprite(
        url: '/uploads/mama_y.png',
        height: 260,
        move: MamaMove.bounce,
        moveKey: 3,
      );
      expect(w.move, MamaMove.bounce);
      expect(w.moveKey, 3);
      expect(w.height, 260);
    });
  });
}
