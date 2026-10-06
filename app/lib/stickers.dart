/// 自定义表情（表情包）本地库：小图存在 App 文档目录，文件名索引存 prefs。
/// 存相对文件名（不存绝对路径）——iOS 更新后容器路径会变，绝对路径会失效。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StickerStore {
  static const _kKey = 'myStickers';
  static const _folder = 'sama_stickers';
  static const maxCount = 80;

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/$_folder');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 已导入的表情文件名列表（新的在前；自动过滤已删除的文件）。
  static Future<List<String>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_kKey) ?? const [];
    final d = await _dir();
    final alive = <String>[];
    for (final n in names) {
      if (await File('${d.path}/$n').exists()) alive.add(n);
    }
    return alive;
  }

  static Future<void> add(Uint8List bytes, String ext) async {
    final d = await _dir();
    final name = 'stk_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File('${d.path}/$name').writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_kKey) ?? [];
    names.insert(0, name);
    if (names.length > maxCount) names.removeRange(maxCount, names.length);
    await prefs.setStringList(_kKey, names);
  }

  static Future<void> remove(String name) async {
    final d = await _dir();
    try {
      await File('${d.path}/$name').delete();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_kKey) ?? [];
    names.remove(name);
    await prefs.setStringList(_kKey, names);
  }

  static Future<File> fileOf(String name) async {
    final d = await _dir();
    return File('${d.path}/$name');
  }

  static Future<Uint8List> bytesOf(String name) async =>
      (await fileOf(name)).readAsBytes();
}
