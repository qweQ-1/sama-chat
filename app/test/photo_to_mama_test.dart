import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/photo_to_mama.dart';

/// 构造纯色画布（RGBA）。
Uint8List _canvas(int w, int h, int r, int g, int b) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = r;
    px[i * 4 + 1] = g;
    px[i * 4 + 2] = b;
    px[i * 4 + 3] = 255;
  }
  return px;
}

void _rect(Uint8List px, int w, int x0, int y0, int x1, int y1, int r, int g,
    int b) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * w + x) * 4;
      px[i] = r;
      px[i + 1] = g;
      px[i + 2] = b;
      px[i + 3] = 255;
    }
  }
}

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

  group('照片分析 · 衣服款式识别（v2.6.1）', () {
    // 脸框固定在 (20,8) 大小 20x20 → 衣服区 y 18~52
    test('横条纹 → 条纹衫(5)', () {
      final px = _canvas(60, 60, 240, 220, 200);
      for (var y = 18; y < 54; y++) {
        final dark = ((y - 18) ~/ 4) % 2 == 0;
        _rect(px, 60, 0, y, 60, y + 1, dark ? 70 : 210, dark ? 70 : 210,
            dark ? 80 : 215);
      }
      expect(detectOutfitStyle(px, 60, 60, 20, 8, 20, 20), 5);
    });

    test('左右同色中间不同 → 西装(4)', () {
      final px = _canvas(60, 60, 240, 220, 200);
      _rect(px, 60, 0, 18, 60, 54, 60, 60, 70); // 深灰外套
      _rect(px, 60, 28, 18, 32, 54, 200, 70, 60); // 中间领带/内搭
      expect(detectOutfitStyle(px, 60, 60, 20, 8, 20, 20), 4);
    });

    test('顶部浅色领 → 衬衫(2)', () {
      final px = _canvas(60, 60, 240, 220, 200);
      _rect(px, 60, 0, 18, 60, 54, 120, 125, 135); // 中灰衬衫
      _rect(px, 60, 24, 18, 36, 26, 245, 245, 245); // 白领
      expect(detectOutfitStyle(px, 60, 60, 20, 8, 20, 20), 2);
    });

    test('纯色 → 默认 T恤(0)', () {
      final px = _canvas(60, 60, 240, 220, 200);
      _rect(px, 60, 0, 18, 60, 54, 90, 140, 200); // 纯蓝
      expect(detectOutfitStyle(px, 60, 60, 20, 8, 20, 20), 0);
    });

    test('衣服没拍到 → 默认 T恤(0)', () {
      final px = _canvas(60, 60, 240, 220, 200);
      expect(detectOutfitStyle(px, 60, 60, 20, 50, 20, 8), 0);
    });
  });
}
