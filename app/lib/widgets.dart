/// Small shared UI pieces.
library;

import 'package:flutter/material.dart';
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
      child: Image.network(
        resolveUrl(context, u),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
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
        child: Image.network(resolveUrl(context, url), fit: BoxFit.contain),
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

String previewOf(Message? m, String? myId) {
  if (m == null) return '';
  final who = (myId != null && m.senderId == myId) ? '我: ' : '';
  return m.isImage ? '$who[图片]' : '$who${m.content}';
}
