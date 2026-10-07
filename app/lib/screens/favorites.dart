/// 收藏消息：本地保存常常要用的消息（地址、账号、笑话…）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../widgets.dart';

class FavoriteItem {
  final String id;
  final String conversationName;
  final String senderName;
  final String type;
  final String content;
  final String fileName;
  final int createdAt;

  FavoriteItem({
    required this.id,
    required this.conversationName,
    required this.senderName,
    required this.type,
    required this.content,
    this.fileName = '',
    required this.createdAt,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> j) => FavoriteItem(
        id: j['id'] as String? ?? '',
        conversationName: j['conversationName'] as String? ?? '',
        senderName: j['senderName'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        content: j['content'] as String? ?? '',
        fileName: j['fileName'] as String? ?? '',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationName': conversationName,
        'senderName': senderName,
        'type': type,
        'content': content,
        'fileName': fileName,
        'createdAt': createdAt,
      };

  String get preview {
    if (type == 'sticker') return '[表情]';
    if (type == 'image') return '[图片]';
    if (type == 'video') return '[视频]';
    if (type == 'voice') return '[语音]';
    if (type == 'file') return '[文件] $fileName';
    return content;
  }
}

/// 收藏存储（prefs JSON）。
class Favorites {
  static const _k = 'favMessages';

  static Future<List<FavoriteItem>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => FavoriteItem.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<FavoriteItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static Future<void> add(FavoriteItem item) async {
    final items = await list();
    items.removeWhere((x) => x.id == item.id);
    items.insert(0, item);
    if (items.length > 200) items.removeRange(200, items.length);
    await _save(items);
  }

  static Future<void> remove(String id) async {
    final items = await list();
    items.removeWhere((x) => x.id == id);
    await _save(items);
  }

  static Future<bool> has(String id) async {
    final items = await list();
    return items.any((x) => x.id == id);
  }
}

/// 收藏列表页。
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await Favorites.list();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 160),
                  EmptyHint(
                      text: '还没有收藏。长按消息 →「收藏」即可保存', icon: Icons.star_outline),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final f = _items[i];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(f.preview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '来自「${f.conversationName}」${f.senderName.isNotEmpty ? ' · ${f.senderName}' : ''} · ${formatTime(f.createdAt)}',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade500),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (f.type == 'text')
                              IconButton(
                                tooltip: '复制',
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: f.content));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('已复制'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                            IconButton(
                              tooltip: '删除',
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: Colors.grey.shade500),
                              onPressed: () async {
                                await Favorites.remove(f.id);
                                _load();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
