/// 聊天表情面板：内置表情（emoji，点按插入输入框）
/// + 我的表情（导入图片变成小表情包，点按直接发送，长按删除）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../image_utils.dart';
import '../stickers.dart';
import '../widgets.dart';

/// 内置表情（常用 emoji）。
const kBuiltinEmojis = <String>[
  '😀', '😁', '😂', '🤣', '😊', '😇', '🙂', '😉', '😍', '🥰',
  '😘', '😋', '😜', '🤪', '😝', '🤗', '🤔', '🤨', '😐', '😶',
  '🙄', '😏', '😴', '😪', '😢', '😭', '😅', '😓', '🥲', '😤',
  '😠', '😡', '🥺', '😳', '🤯', '🥳', '🥴', '🤢', '🤧', '😷',
  '👻', '💀', '👽', '🤖', '💩', '😺', '😹', '🙀', '👍', '👎',
  '👏', '🙌', '🤝', '🙏', '💪', '✌️', '🤞', '👌', '👋', '🤙',
  '✊', '👊', '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '💔',
  '💕', '💓', '💖', '💘', '✨', '⭐', '🌟', '💫', '🔥', '💥',
  '💦', '💨', '🎉', '🎊', '🎁', '🎂', '🍰', '🍕', '🍔', '🍟',
  '🍜', '🍦', '☕', '🍺', '🍎', '🍉', '🍓', '🌹', '🌸', '🌈',
  '☀️', '🌙', '🤡', '🐶', '🐱', '🐼', '🐸', '🦄', '🐟', '🦋',
];

class StickerPanel extends StatefulWidget {
  final void Function(String emoji) onEmoji;
  final void Function(Uint8List bytes, String ext) onSticker;

  const StickerPanel({
    super.key,
    required this.onEmoji,
    required this.onSticker,
  });

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  int _tab = 0;
  List<({String name, File file})> _my = const [];
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final names = await StickerStore.list();
    final files = <({String name, File file})>[];
    for (final n in names) {
      files.add((name: n, file: await StickerStore.fileOf(n)));
    }
    if (mounted) setState(() => _my = files);
  }

  Future<void> _import() async {
    if (_importing) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (x == null) return;
      final raw = await x.readAsBytes();
      final ext0 = x.name.contains('.') ? x.name.split('.').last : 'png';
      final small = await makeSticker(raw, fallbackExt: ext0);
      await StickerStore.add(small.bytes, small.ext);
      await _load();
      if (mounted) setState(() => _tab = 1);
      messenger.showSnackBar(const SnackBar(
        content: Text('已添加为表情 ✓ 点它就能发出去'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('导入失败：$e'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _send(String name) async {
    try {
      final bytes = await StickerStore.bytesOf(name);
      final ext = name.contains('.') ? name.split('.').last : 'png';
      widget.onSticker(bytes, ext);
    } catch (_) {
      if (mounted) showError(context, '表情读取失败，请重试');
    }
  }

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除表情'),
        content: const Text('把这个表情从「我的表情」里删掉？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await StickerStore.remove(name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 264,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Row(children: [
            _tabBtn('😀', '表情', 0),
            _tabBtn('🖼️', '我的表情', 1),
          ]),
          const Divider(height: 1),
          Expanded(child: _tab == 0 ? _emojiGrid() : _myGrid()),
        ],
      ),
    );
  }

  Widget _tabBtn(String icon, String label, int idx) {
    final active = _tab == idx;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? scheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text('$icon $label',
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? scheme.primary : Colors.grey.shade600,
            )),
      ),
    );
  }

  Widget _emojiGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: kBuiltinEmojis.length,
      itemBuilder: (context, i) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onEmoji(kBuiltinEmojis[i]),
        child: Center(
          child: Text(kBuiltinEmojis[i], style: const TextStyle(fontSize: 25)),
        ),
      ),
    );
  }

  Widget _myGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _my.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _addTile();
        final st = _my[i - 1];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _send(st.name),
          onLongPress: () => _delete(st.name),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Image.file(st.file, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        );
      },
    );
  }

  Widget _addTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _importing ? null : _import,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: _importing
            ? const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: Colors.grey.shade500, size: 26),
                  const SizedBox(height: 4),
                  Text('导入图片',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
      ),
    );
  }
}
