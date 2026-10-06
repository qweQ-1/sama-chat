import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../image_utils.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class MomentsTab extends StatelessWidget {
  const MomentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('炫圈', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: '发布动态',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ComposeMomentScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => s.refreshMoments(),
        child: s.moments.isEmpty
            ? ListView(children: const [
                SizedBox(height: 180),
                EmptyHint(text: '还没有动态，点右上角分享第一条炫圈吧', icon: Icons.public),
              ])
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: s.moments.length,
                itemBuilder: (context, i) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: MomentCard(moment: s.moments[i]),
                  ),
                ),
              ),
      ),
    );
  }
}

class MomentCard extends StatelessWidget {
  final Moment moment;
  const MomentCard({super.key, required this.moment});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final m = moment;
    final isMine = s.me != null && m.author?.id == s.me!.id;
    final fresh = serverNowMs() - m.createdAt < 2 * 60 * 1000;

    return GestureDetector(
      onLongPress: isMine ? () => _tryDelete(context, s, m) : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: m.author?.displayName ?? '?', url: m.author?.avatar, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.author?.displayName ?? '未知用户',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(formatTime(m.createdAt),
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
              if (isMine && fresh)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => _tryDelete(context, s, m),
                  child: Text('删除',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade500)),
                ),
            ],
          ),
          if (m.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
              child: Text(m.text, style: const TextStyle(fontSize: 15, height: 1.35)),
            ),
          if (m.images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _ImageGrid(images: m.images),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionChip(
                icon: m.likedByMe ? Icons.favorite : Icons.favorite_border,
                label: m.likeCount > 0 ? '${m.likeCount}' : '赞',
                active: m.likedByMe,
                onTap: () => s.toggleLike(m.id),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.mode_comment_outlined,
                label: m.comments.isNotEmpty ? '${m.comments.length}' : '评论',
                active: false,
                onTap: () => _showCommentSheet(context, s, m.id),
              ),
            ],
          ),
          if (m.comments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light
                    ? const Color(0xFFF4F4F8)
                    : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: m.comments
                    .map((c) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${c.author?.displayName ?? '?'}：',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5B5BD6),
                                    fontSize: 13.5),
                              ),
                              TextSpan(
                                  text: c.text,
                                  style: const TextStyle(fontSize: 13.5)),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Future<void> _tryDelete(BuildContext context, AppState s, Moment m) async {
    if (m.author?.id != s.me?.id) return;
    if (serverNowMs() - m.createdAt >= 2 * 60 * 1000) {
      showError(context, '发布超过 2 分钟，不能删除啦');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('删除后其他人都将看不到这条炫圈，确定删除吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.deleteMoment(m.id);
      if (context.mounted) showError(context, '已删除');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    } catch (e) {
      if (context.mounted) showError(context, '删除失败: $e');
    }
  }

  void _showCommentSheet(BuildContext context, AppState s, String momentId) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '写评论…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await s.addComment(momentId, text);
                } on ApiException catch (e) {
                  if (context.mounted) showError(context, e.message);
                }
              },
              child: const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFE0245E) : Colors.grey.shade600;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFE0245E).withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> images;
  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final n = images.length;
    final cross = n == 1 ? 1 : (n <= 4 ? 2 : 3);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: n,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ImageViewerScreen(url: images[i])),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: NetImage(
            url: images[i],
            errorBuilder: (_) => Container(
              color: Colors.grey.shade200,
              child:
                  const Icon(Icons.broken_image_outlined, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compose a new moment: text + up to 9 images.
class ComposeMomentScreen extends StatefulWidget {
  const ComposeMomentScreen({super.key});

  @override
  State<ComposeMomentScreen> createState() => _ComposeMomentScreenState();
}

class _ComposeMomentScreenState extends State<ComposeMomentScreen> {
  final _text = TextEditingController();
  final List<({Uint8List bytes, String ext})> _images = [];
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_images.length >= 9) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 82,
    );
    for (final f in files) {
      if (_images.length >= 9) break;
      final raw = await f.readAsBytes();
      final ext0 = f.name.contains('.') ? f.name.split('.').last : 'jpg';
      final img = await compressImage(raw, fallbackExt: ext0);
      setState(() => _images.add((bytes: img.bytes, ext: img.ext)));
    }
  }

  Future<void> _publish() async {
    if (_text.text.trim().isEmpty && _images.isEmpty) {
      showError(context, '写点文字或选张图片吧');
      return;
    }
    setState(() => _busy = true);
    final s = context.read<AppState>();
    try {
      await s.publishMoment(_text.text.trim(), List.of(_images));
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发布失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布炫圈'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _publish,
            child: _busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('发布', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: '这一刻的想法…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._images.asMap().entries.map((e) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(e.value.bytes,
                            width: 90, height: 90, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _images.removeAt(e.key)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )),
              if (_images.length < 9)
                InkWell(
                  onTap: _pick,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
