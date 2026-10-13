import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/mama_sprite.dart';
import 'package:samachat/models.dart';

void main() {
  group('mama秀 动作帧（v2.8.1）', () {
    test('动作类型齐全', () {
      expect(SpriteAction.values, contains(SpriteAction.idle));
      expect(SpriteAction.values, contains(SpriteAction.wave));
      expect(SpriteAction.values.length, 2);
    });

    test('MamaSprite 默认参数', () {
      const w = MamaSprite(url: '/uploads/mama_x.png');
      expect(w.action, SpriteAction.idle);
      expect(w.frames, isEmpty);
      expect(w.height, 110);
    });

    test('MamaSprite 带动作帧', () {
      const w = MamaSprite(
        url: '/uploads/mama_x.png',
        frames: ['/uploads/mama_wave_a.png', '/uploads/mama_wave_b.png'],
        height: 260,
        action: SpriteAction.wave,
        actionKey: 1,
      );
      expect(w.frames.length, 2);
      expect(w.action, SpriteAction.wave);
      expect(w.actionKey, 1);
    });

    test('TappableSprite 默认无动作帧（不播放）', () {
      const w = TappableSprite(url: '/uploads/mama_y.png');
      expect(w.frames, isEmpty);
      expect(w.height, 170);
    });
  });

  group('User.mamaFrames 解析（v2.8.1）', () {
    test('解析动作帧映射', () {
      final u = User.fromJson({
        'id': 'u1',
        'username': 'a',
        'displayName': 'A',
        'mamaImage': '/uploads/mama_1.png',
        'mamaFrames': {
          'wave': ['/uploads/mama_wave_1.png', '/uploads/mama_wave_2.png'],
        },
      });
      expect(u.mamaImage, '/uploads/mama_1.png');
      expect(u.mamaFrames['wave']?.length, 2);
      expect(u.mamaFrames['wave']?[0], '/uploads/mama_wave_1.png');
    });

    test('无动作帧时为空映射', () {
      final u = User.fromJson({'id': 'u2', 'username': 'b', 'displayName': 'B'});
      expect(u.mamaFrames, isEmpty);
      expect(u.mamaFrames['wave'], null);
    });

    test('空帧数组也能解析', () {
      final u = User.fromJson({
        'id': 'u3',
        'username': 'c',
        'displayName': 'C',
        'mamaFrames': {'wave': []},
      });
      expect(u.mamaFrames['wave'], isEmpty);
    });
  });
}
