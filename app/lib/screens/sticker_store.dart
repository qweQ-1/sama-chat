/// 表情商店：浏览所有人的表情包、下载到本地、发布自己的表情包。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../image_utils.dart';
import '../models.dart';
import '../store.dart';
import '../stickers.dart';
import '../widgets.dart';

class StickerStoreScreen extends StatefulWidget {
  const StickerStoreScreen({super.key});

  @override
  State<StickerStoreScreen> createState() => _StickerStoreScreenState();
}

class _StickerStoreScreenState extends State<StickerStoreScreen> {
  List<StickerPack> _packs = [];
  List<StickerPack> _mine = []; // 我下载过的
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = context.read<AppState>();
      final store = await s.api.stickerStore();
      final mine = await StickerStore.packs();
      // 服务端里我下载过但本地缓存的，以服务端为准补充
      final downloaded = await s.api.downloadedPacks();
      final merged = <String, StickerPack>{};
      for (final p in [...mine, ...downloaded]) {
        merged[p.id] = p;
      }
      if (!mounted) return;
      setState(() {
        _packs = store;
        _mine = merged.values.toList();
        _loading = false;
      });
      // 同步本地缓存
      await StickerStore.savePacks(_mine);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _download(StickerPack p) async {
    if (_busy.contains(p.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(p.id));
    try {
      final updated = await context.read<AppState>().api.downloadStickerPack(p.id);
      await StickerStore.addPack(updated);
      if (!mounted) return;
      setState(() {
        final i = _packs.indexWhere((x) => x.id == p.id);
        if (i >= 0) _packs[i] = updated;
        _mine.removeWhere((x) => x.id == p.id);
        _mine.insert(0, updated);
      });
      messenger.showSnackBar(SnackBar(
        content: Text('已下载「${p.name}」✓ 聊天表情面板里可直接用'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) showError(context, '下载失败：${e.message}');
    } catch (e) {
      if (mounted) showError(context, '下载失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _removeMine(StickerPack p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除表情包'),
        content: Text('从本地移除「${p.name}」？\n（商店里仍然可以重新下载）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (ok != true) return;
    await StickerStore.removePack(p.id);
    if (mounted) {
      setState(() => _mine.removeWhere((x) => x.id == p.id));
    }
  }

  Future<void> _openPublish() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PublishStickerPackScreen()),
    );
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('表情商店'),
        actions: [
          IconButton(
            tooltip: '发布我的表情包',
            onPressed: _openPublish,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.orange.shade50,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline,
                            color: Colors.orange),
                        title: Text('商店加载失败：$_error',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: const Text('需要服务器更新到 v2.0.5 才支持表情商店',
                            style: TextStyle(fontSize: 12)),
                        trailing: TextButton(
                            onPressed: _load, child: const Text('重试')),
                      ),
                    ),
                  if (_mine.isNotEmpty) ...[
                    _sectionTitle('我的表情包（已下载）', Icons.download_done),
                    for (final p in _mine)
                      _PackCard(
                        pack: p,
                        downloaded: true,
                        busy: _busy.contains(p.id),
                        onDownload: null,
                        onRemove: () => _removeMine(p),
                        onDelete: null,
                      ),
                    const SizedBox(height: 8),
                  ],
                  _sectionTitle('商店 · 大家的作品', Icons.storefront_outlined),
                  if (_packs.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '商店还空空的——点右上角「+」发布第一个表情包吧！',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ),
                  for (final p in _packs)
                    _PackCard(
                      pack: p,
                      downloaded: p.downloaded,
                      busy: _busy.contains(p.id),
                      onDownload: p.downloaded ? null : () => _download(p),
                      onRemove: null,
                      onDelete: p.authorId ==
                              context.read<AppState>().me?.id
                          ? () => _deletePack(p)
                          : null,
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _deletePack(StickerPack p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除表情包'),
        content: Text('确定删除「${p.name}」？所有人将无法再下载它。'),
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
    try {
      await context.read<AppState>().api.deleteStickerPack(p.id);
      if (mounted) setState(() => _packs.removeWhere((x) => x.id == p.id));
    } on ApiException catch (e) {
      if (mounted) showError(context, '删除失败：${e.message}');
    }
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(text,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _PackCard extends StatelessWidget {
  final StickerPack pack;
  final bool downloaded;
  final bool busy;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;
  final VoidCallback? onDelete;

  const _PackCard({
    required this.pack,
    required this.downloaded,
    required this.busy,
    required this.onDownload,
    required this.onRemove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pack.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '@${pack.authorName} · ${pack.stickers.length} 个表情 · ${pack.downloads} 次下载',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pack.stickers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) => Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: NetImage(
                    url: pack.stickers[i],
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                    errorBuilder: (_) => const SizedBox(
                      width: 50,
                      height: 50,
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.grey, size: 20),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除', style: TextStyle(fontSize: 12.5)),
                  ),
                if (onRemove != null)
                  TextButton.icon(
                    onPressed: busy ? null : onRemove,
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: const Text('移除', style: TextStyle(fontSize: 12.5)),
                  ),
                if (onDownload != null)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onDownload,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download, size: 16),
                    label: const Text('下载', style: TextStyle(fontSize: 12.5)),
                  )
                else if (downloaded && onRemove == null)
                  Text('已下载 ✓',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 发布我的表情包：起名 → 选图（支持 GIF 动图）→ 逐个上传 → 发布。
class PublishStickerPackScreen extends StatefulWidget {
  const PublishStickerPackScreen({super.key});

  @override
  State<PublishStickerPackScreen> createState() =>
      _PublishStickerPackScreenState();
}

class _PublishStickerPackScreenState extends State<PublishStickerPackScreen> {
  final _name = TextEditingController();
  final List<({Uint8List bytes, String ext})> _items = [];
  bool _importing = false;
  bool _publishing = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addImages() async {
    if (_importing || _items.length >= 50) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      final files = await ImagePicker().pickMultiImage();
      for (final f in files) {
        if (_items.length >= 50) break;
        final raw = await f.readAsBytes();
        final ext0 = f.name.contains('.') ? f.name.split('.').last : 'png';
        // GIF 动图保持原样（不压缩，否则动画丢失）；其余压成小图。
        final small = ext0.toLowerCase() == 'gif'
            ? (bytes: raw, ext: 'gif')
            : await makeSticker(raw, fallbackExt: ext0);
        setState(() => _items.add((bytes: small.bytes, ext: small.ext)));
      }
      messenger.showSnackBar(SnackBar(
        content: Text('已添加 ${_items.length} 个表情（GIF 动图会保留动画）'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('选择图片失败：$e'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _publish() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showError(context, '给表情包起个名字吧');
      return;
    }
    if (_items.isEmpty) {
      showError(context, '至少添加 1 个表情');
      return;
    }
    final s = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _publishing = true);
    try {
      final urls = <String>[];
      for (final it in _items) {
        urls.add(await s.api.uploadImage(it.bytes, it.ext));
      }
      await s.api.publishStickerPack(name, urls);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text('「$name」已发布到表情商店 ✓'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) showError(context, '发布失败：${e.message}');
    } catch (e) {
      if (mounted) showError(context, '发布失败：$e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布表情包')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _name,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '表情包名字',
                hintText: '比如：小狗日常、猫猫大笑…',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.info_outline, size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '支持图片和 GIF 动图；发布后所有人都能在商店下载使用',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _items.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _importing ? null : _addImages,
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
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    color: Colors.grey.shade500, size: 26),
                                const SizedBox(height: 4),
                                Text('选图/GIF',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              ],
                            ),
                    ),
                  );
                }
                final it = _items[i - 1];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.memory(it.bytes,
                          fit: BoxFit.contain, gaplessPlayback: true),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: () =>
                            setState(() => _items.removeAt(i - 1)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: FilledButton.icon(
                onPressed: _publishing ? null : _publish,
                icon: _publishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.publish),
                label: Text(_publishing
                    ? '发布中…'
                    : '发布到表情商店（${_items.length} 个表情）'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
