/// Small shared UI pieces.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'store.dart';

/// Deterministic pastel color from any string seed.
Color colorFor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0xffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.50, 0.52).toColor();
}

/// Resolve a possibly-relative image URL against the configured server.
String resolveUrl(BuildContext context, String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = context.read<AppState>().serverBase;
  return '$base$url';
}

/// 全 App 图片磁盘缓存（桌面端也用 JSON 索引，无需 sqlite 插件）。
final CacheManager imageCacheManager = CacheManager(
  Config(
    'samaImages',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 800,
    repo: JsonCacheInfoRepository(databaseName: 'samaImages'),
    fileSystem: IOFileSystem('samaImages'),
  ),
);

/// 带磁盘缓存的网络图片：看过的图第二次打开直接本地秒出，不再走网络。
class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? errorBuilder;
  final Widget? placeholder;

  const NetImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: resolveUrl(context, url),
      cacheManager: imageCacheManager,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, _) =>
          placeholder ??
          Container(
            width: width,
            height: height,
            color: Colors.black.withValues(alpha: 0.05),
          ),
      errorWidget: (context, _, __) =>
          errorBuilder?.call(context) ??
          Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;

  const Avatar({super.key, required this.name, this.url, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final u = url;
    final hasImage = u != null && u.isNotEmpty;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorFor(name),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        name.isNotEmpty ? name.characters.first : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (!hasImage) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: NetImage(
        url: u,
        width: size,
        height: size,
        errorBuilder: (_) => fallback,
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyHint({super.key, required this.text, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }
}

/// Full-screen image viewer (tap image to open).
class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String? heroTag;
  const ImageViewerScreen({super.key, required this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final img = InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: NetImage(
          url: url,
          fit: BoxFit.contain,
          placeholder: const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: heroTag != null ? Hero(tag: heroTag!, child: img) : img,
    );
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
  ));
}

/// 显示未读公告（同一条只弹一次；关闭后立即标记已读）。
/// 在主页 shell 的 build 里调用即可（内部有防重入与空判断）。
void maybeShowAnnouncements(BuildContext context) {
  final s = context.read<AppState>();
  if (s.pendingAnnouncements.isEmpty || s.announcementShown) return;
  s.announcementShown = true;
  final anns = List<Announcement>.of(s.pendingAnnouncements);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) {
      s.announcementShown = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.campaign_outlined, size: 22),
          SizedBox(width: 8),
          Text('公告'),
        ]),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < anns.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  Text(anns[i].content,
                      style: const TextStyle(fontSize: 14.5, height: 1.55)),
                  const SizedBox(height: 6),
                  Text(
                    '—— ${anns[i].authorName} · ${formatTime(anns[i].createdAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
    s.announcementShown = false;
    await s.ackAnnouncements();
  });
}

String previewOf(Message? m, String? myId) {
  if (m == null) return '';
  final who = (myId != null && m.senderId == myId) ? '我: ' : '';
  if (m.recalled) return '$who[已撤回]';
  if (m.isSticker) return '$who[表情]';
  if (m.isImage) return '$who[图片]';
  if (m.isVideo) return '$who[视频]';
  return '$who${m.content}';
}
