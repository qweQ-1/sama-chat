import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/photo_to_mama.dart';

void main() {
  group('照片分析 · 颜色映射（v2.6.0）', () {
    test('肤色 5 档（按亮度）', () {
      expect(mapSkin(const Color(0xFFFFF0E6)), 0); // 很浅
      expect(mapSkin(const Color(0xFFF0C8A0)), 1);
      expect(mapSkin(const Color(0xFFDCA26F)), 2);
      expect(mapSkin(const Color(0xFFAA7B52)), 3);
      expect(mapSkin(const Color(0xFF6B4423)), 4); // 深棕
    });

    test('发色 6 档（最近邻）', () {
      expect(mapHair(const Color(0xFF222222)), 0); // 黑
      expect(mapHair(const Color(0xFF6D4A2F)), 1); // 棕
      expect(mapHair(const Color(0xFFE8C04E)), 2); // 金
      expect(mapHair(const Color(0xFFC94B3C)), 3); // 红
      expect(mapHair(const Color(0xFF4A6FBF)), 4); // 蓝
      expect(mapHair(const Color(0xFFE88BB5)), 5); // 粉
    });

    test('衣服颜色：灰阶分白/黑', () {
      expect(mapOutfit(const Color(0xFFF5F5F5)), 0); // 白
      expect(mapOutfit(const Color(0xFF222222)), 1); // 黑
      expect(mapOutfit(const Color(0xFF666666)), 1); // 深灰 → 黑
    });

    test('衣服颜色：彩色按色相', () {
      expect(mapOutfit(const Color(0xFFE03030)), 2); // 红
      expect(mapOutfit(const Color(0xFF2E5FD0)), 3); // 蓝
      expect(mapOutfit(const Color(0xFF2EA04E)), 4); // 绿
      expect(mapOutfit(const Color(0xFFE8C84A)), 5); // 黄
    });
  });
}
