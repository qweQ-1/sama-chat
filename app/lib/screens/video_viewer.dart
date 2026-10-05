import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 全屏视频播放器（聊天中点视频卡片进来）。
class VideoViewerScreen extends StatefulWidget {
  final String url;
  const VideoViewerScreen({super.key, required this.url});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _controller = c);
    } catch (_) {
      c.dispose();
      if (mounted) setState(() => _error = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('视频', style: TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: _error
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('视频加载失败，请检查网络后重试',
                    style: TextStyle(color: Colors.white70)),
              )
            : c == null
                ? const CircularProgressIndicator()
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTap: _togglePlay,
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(c),
                              if (!c.value.isPlaying)
                                const Icon(Icons.play_circle_fill,
                                    size: 64, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.white,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
