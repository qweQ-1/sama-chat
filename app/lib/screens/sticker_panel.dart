/// 聊天表情面板：
/// ① 表情（内置 emoji，点按插入输入框）
/// ② 我的表情（本地导入的图片/GIF 小表情，点按直接发送，长按删除）
/// ③ 表情包（从表情商店下载的整合包，点按直接发送）
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../image_utils.dart';
import '../models.dart';
import '../store.dart';
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
  final void Function(String url) onStickerUrl;
  final VoidCallback? onOpenStore;

  const StickerPanel({
    super.key,
    required this.onEmoji,
    required this.onSticker,
    required this.onStickerUrl,
    this.onOpenStore,
  });

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  int _tab = 0;
  List<({String name, File file})> _my = const [];
  bool _importing = false;

  List<StickerPack> _packs = const [];
  int _packIdx = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPacks();
  }

  Future<void> _load() async {
    final names = await StickerStore.list();
    final files = <({String name, File file})>[];
    for (final n in names) {
      files.add((name: n, file: await StickerStore.fileOf(n)));
    }
    if (mounted) setState(() => _my = files);
  }

  Future<void> _loadPacks() async {
    // 先显示本地缓存，随后静默刷新（同步其它设备/重装后的下载记录）。
    final local = await StickerStore.packs();
    if (mounted && local.isNotEmpty) setState(() => _packs = local);
    try {
      final s = context.read<AppState>();
      final remote = await s.api.downloadedPacks();
      if (remote.isNotEmpty || local.isEmpty) {
        await StickerStore.savePacks(remote);
        if (mounted) {
          setState(() {
            _packs = remote;
            if (_packIdx >= _packs.length) _packIdx = 0;
          });
        }
      }
    } catch (_) {/* 离线时用本地缓存 */}
  }

  Future<void> _import() async {
    if (_importing) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      // 注意：不能传 maxWidth/maxHeight，否则 GIF 会被缩放成静图
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final raw = await x.readAsBytes();
      final ext0 = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'png';
      // GIF 动图保持原样（缩放会丢动画）；其余压成小图。
      final small = isAnimatedGif(raw, ext0)
          ? (bytes: raw, ext: 'gif')
          : await makeSticker(raw, fallbackExt: ext0);
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
            _tabBtn('🧩', '表情包', 2),
            const Spacer(),
            if (_tab == 2)
              IconButton(
                tooltip: '打开表情商店',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.storefront_outlined,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                onPressed: () async {
                  widget.onOpenStore?.call();
                  // 从商店回来后刷新（可能刚下载了新表情包）
                  await Future<void>.delayed(const Duration(milliseconds: 400));
                  _loadPacks();
                },
              ),
          ]),
          const Divider(height: 1),
          Expanded(
            child: _tab == 0
                ? _emojiGrid()
                : (_tab == 1 ? _myGrid() : _packsArea()),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  Text('导入图片/GIF',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
      ),
    );
  }

  /// 「表情包」分区：横向选择表情包 + 网格展示 + 直达商店。
  Widget _packsArea() {
    if (_packs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('还没有表情包',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('去商店下载大家的作品，或用「+」发布自己的',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () async {
                widget.onOpenStore?.call();
                await Future<void>.delayed(const Duration(milliseconds: 400));
                _loadPacks();
              },
              icon: const Icon(Icons.storefront, size: 18),
              label: const Text('打开表情商店'),
            ),
          ],
        ),
      );
    }

    if (_packIdx >= _packs.length) _packIdx = 0;
    final pack = _packs[_packIdx];

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: _packs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final active = i == _packIdx;
              final scheme = Theme.of(context).colorScheme;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _packIdx = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? scheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    border: Border.all(
                      color: active ? scheme.primary : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _packs[i].name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? scheme.primary : Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: pack.stickers.length,
            itemBuilder: (context, i) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onStickerUrl(pack.stickers[i]),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: NetImage(
                  url: pack.stickers[i],
                  fit: BoxFit.contain,
                  errorBuilder: (_) => const Icon(Icons.broken_image_outlined,
                      color: Colors.grey, size: 20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
