import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../image_utils.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'group_info.dart';
import 'sticker_panel.dart';
import 'sticker_store.dart';
import 'video_viewer.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  bool _showPanel = false; // 表情面板展开中
  final _picker = ImagePicker();
  AppState? _state;
  Timer? _typingTimer;
  bool _sentTypingFalse = true;
  bool _loading = true;
  bool _sendingMedia = false;

  String get convId => widget.conversation.id;

  /// 已播过入场动画的消息 id（避免列表复用时重复播放）
  final Set<String> _animatedOnce = {};

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _state = s;
    s.activeChatId = convId;
    _bootstrap(s);
  }

  Future<void> _bootstrap(AppState s) async {
    try {
      await s.loadMessages(convId);
      await s.markConversationRead(convId);
    } catch (e) {
      if (mounted) showError(context, '加载消息失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    final s = _state;
    if (s != null) {
      if (s.activeChatId == convId) s.activeChatId = null;
      _typingTimer?.cancel();
      if (!_sentTypingFalse) s.sendTyping(convId, false);
    }
    _input.dispose();
    super.dispose();
  }

  void _onInputChanged(String _) {
    final s = _state;
    if (s == null) return;
    s.sendTyping(convId, true);
    _sentTypingFalse = false;
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1600), () {
      _state?.sendTyping(convId, false);
      _sentTypingFalse = true;
    });
  }

  Future<void> _send() async {
    final s = context.read<AppState>();
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    s.sendTyping(convId, false);
    _sentTypingFalse = true;
    try {
      await s.sendText(convId, text);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  /// 在输入框光标处插入一个表情。
  void _insertEmoji(String e) {
    final text = _input.text;
    final sel = _input.selection;
    if (sel.isValid && sel.start >= 0 && sel.end >= sel.start) {
      final newText = text.replaceRange(sel.start, sel.end, e);
      _input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + e.length),
      );
    } else {
      _input.text = text + e;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
  }

  /// 发送自定义表情（小图，上传后以 sticker 类型发出）。
  Future<void> _sendSticker(Uint8List bytes, String ext) async {
    final s = context.read<AppState>();
    try {
      await s.sendSticker(convId, bytes, ext);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (_) {
      if (mounted) showError(context, '表情发送失败，请重试');
    }
  }

  /// 发送表情包里的表情（服务器已有，直接引用 URL）。
  Future<void> _sendStickerUrl(String url) async {
    final s = context.read<AppState>();
    try {
      await s.sendStickerUrl(convId, url);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (_) {
      if (mounted) showError(context, '表情发送失败，请重试');
    }
  }

  /// 打开表情商店（返回后刷新面板）。
  Future<void> _openStore() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StickerStoreScreen()),
    );
  }

  Future<void> _sendImage() async {
    final s = context.read<AppState>();
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (x == null) return;
      setState(() => _sendingMedia = true);
      final raw = await x.readAsBytes();
      final ext0 = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final img = await compressImage(raw, fallbackExt: ext0);
      await s.sendImage(convId, img.bytes, img.ext);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发送图片失败: $e');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _sendVideo(ImageSource source) async {
    final s = context.read<AppState>();
    try {
      final x = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 3),
      );
      if (x == null) return;
      final len = await x.length();
      if (len > 40 * 1024 * 1024) {
        if (mounted) showError(context, '视频太大了（限 40MB，约 1 分钟）');
        return;
      }
      setState(() => _sendingMedia = true);
      final bytes = await x.readAsBytes();
      final ext =
          x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'mp4';
      await s.sendVideo(convId, bytes, ext);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发送视频失败: $e');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('图片'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('视频（从相册选择）'),
              subtitle: const Text('最长 3 分钟 · 限 40MB',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            if (Platform.isAndroid || Platform.isIOS)
              ListTile(
                leading: const Icon(Icons.video_camera_back_outlined),
                title: const Text('拍摄视频'),
                subtitle: const Text('最长 3 分钟 · 限 40MB',
                    style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'image') {
      await _sendImage();
    } else if (choice == 'video') {
      await _sendVideo(ImageSource.gallery);
    } else if (choice == 'camera') {
      await _sendVideo(ImageSource.camera);
    }
  }

  /// 拿最新的会话数据（群名/人数可能已被修改）
  Conversation _currentConv(AppState s) {
    return s.conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
      orElse: () => widget.conversation,
    );
  }

  /// 群是否已不属于我（被解散 / 我已退出）→ 输入区换成提示。
  bool get _goneFromList {
    final s = _state;
    if (s == null || !widget.conversation.isGroup) return false;
    return !s.conversations.any((c) => c.id == convId);
  }

  void _popToChats() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
  }

  Future<void> _confirmRecall(Message m) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确定要撤回这条消息吗？（对方将看到"已撤回"）'),        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('撤回')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.recallMessage(m.conversationId, m.id);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    final msgs = List<Message>.from(s.chatMessages[convId] ?? const []);
    msgs.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
    final typers = (s.typingIn[convId] ?? const <String>{})
        .where((u) => u != me?.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: widget.conversation.isGroup
              ? () async {
                  final conv = _currentConv(s);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupInfoScreen(conversation: conv),
                    ),
                  );
                  if (mounted) {
                    s.refreshConversations();
                  }
                }
              : null,
          child: Column(
            children: [
              Text(
                _currentConv(s).name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (widget.conversation.isGroup)
                Text('共 ${_currentConv(s).memberCount} 人',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : msgs.isEmpty
                    ? const EmptyHint(text: '开始聊天吧 👋', icon: Icons.chat_outlined)
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: msgs.length,
                        itemBuilder: (context, i) {
                          final m = msgs[i];
                          final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                          final showTime = older == null ||
                              m.createdAt - older.createdAt > 5 * 60 * 1000;
                          final isFresh = !_animatedOnce.contains(m.id) &&
                              serverNowMs() - m.createdAt < 3000;
                          if (isFresh) _animatedOnce.add(m.id);
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOut,
                            transitionBuilder: (child, anim) =>
                                FadeTransition(opacity: anim, child: child),
                            child: _AnimatedAppear(
                              key: ValueKey('${m.id}-${m.recalled}'),
                              play: isFresh,
                              child: _Bubble(
                                message: m,
                                isMine: m.senderId == me?.id,
                                isGroup: widget.conversation.isGroup,
                                showTime: showTime,
                                isLastMine: i == 0 && m.senderId == me?.id,
                                othersRead: m.readBy.any((r) => r != me?.id),
                                canRecall: m.senderId == me?.id &&
                                    !m.recalled &&
                                    !m.pending &&
                                    !m.failed &&
                                    serverNowMs() - m.createdAt <
                                        24 * 60 * 60 * 1000,
                                onRecall: () => _confirmRecall(m),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (typers.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 20, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _TypingDots(),
              ),
            ),
          if (_goneFromList)
            _LeftGroupBar(onBack: _popToChats)
          else
            SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InputBar(
            controller: _input,
            onChanged: _onInputChanged,
            onSend: _send,
            onAttach: _pickAttachment,
            sendingMedia: _sendingMedia,
            panelOpen: _showPanel,
            onToggleEmoji: () => setState(() {
              _showPanel = !_showPanel;
              if (_showPanel) FocusScope.of(context).unfocus();
            }),
            onFieldTap: () {
              if (_showPanel) setState(() => _showPanel = false);
            },
          ),
          if (_showPanel)
            StickerPanel(
              onEmoji: _insertEmoji,
              onSticker: _sendSticker,
              onStickerUrl: _sendStickerUrl,
              onOpenStore: _openStore,
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftGroupBar extends StatelessWidget {
  final VoidCallback onBack;
  const _LeftGroupBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '你已不在这个群聊里',
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('返回聊天列表'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool sendingMedia;
  final bool panelOpen;
  final VoidCallback onToggleEmoji;
  final VoidCallback onFieldTap;

  const _InputBar({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
    required this.sendingMedia,
    required this.panelOpen,
    required this.onToggleEmoji,
    required this.onFieldTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: sendingMedia ? null : onAttach,
              icon: sendingMedia
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onTap: onFieldTap,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '发消息…',
                  isDense: true,
                  suffixIcon: IconButton(
                    onPressed: onToggleEmoji,
                    visualDensity: VisualDensity.compact,
                    tooltip: panelOpen ? '收起表情' : '表情',
                    icon: Icon(
                      panelOpen
                          ? Icons.keyboard_alt_outlined
                          : Icons.emoji_emotions_outlined,
                      size: 22,
                    ),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.light
                      ? Colors.grey.shade100
                      : Colors.grey.shade900,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool isGroup;
  final bool showTime;
  final bool isLastMine;
  final bool othersRead;
  final bool canRecall;
  final VoidCallback? onRecall;

  const _Bubble({
    required this.message,
    required this.isMine,
    required this.isGroup,
    required this.showTime,
    required this.isLastMine,
    required this.othersRead,
    this.canRecall = false,
    this.onRecall,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final senderName = message.sender?.displayName ?? '';

    if (message.recalled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            isMine
                ? '你撤回了一条消息'
                : '${senderName.isEmpty ? '对方' : senderName} 撤回了一条消息',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5),
          ),
        ),
      );
    }

    Widget content = message.isVideo
        ? _videoBubble(context, message)
        : message.isSticker
        ? NetImage(
            url: message.content,
            width: 132,
            height: 132,
            fit: BoxFit.contain,
            errorBuilder: (_) => const SizedBox(
              width: 132,
              height: 132,
              child: Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey, size: 32),
              ),
            ),
          )
        : message.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: NetImage(
              url: message.content,
              width: 180,
              errorBuilder: (_) => Container(
                width: 180,
                height: 120,
                color: Colors.grey.shade300,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: isMine ? scheme.primary : (Theme.of(context).brightness == Brightness.light ? Colors.white : scheme.surfaceContainerHighest),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              boxShadow: isMine
                  ? null
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: isMine ? Colors.white : null,
                fontSize: 15.5,
                height: 1.3,
              ),
            ),
          );

    if (message.isImage) {
      content = GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(url: message.content),
          ),
        ),
        child: content,
      );
    }

    if (canRecall && onRecall != null) {
      content = GestureDetector(
        onLongPress: onRecall,
        child: content,
      );
    }

    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showTime)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                formatTime(message.createdAt),
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine && isGroup) ...[
                Avatar(name: senderName, url: message.sender?.avatar, size: 34),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isMine && isGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3, left: 2),
                        child: Text(
                          senderName,
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade500),
                        ),
                      ),
                    content,
                    if (isMine && (message.pending || message.failed))
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 2),
                        child: Icon(
                          message.failed
                              ? Icons.error_outline
                              : Icons.access_time,
                          size: 11,
                          color: message.failed
                              ? Colors.redAccent
                              : Colors.grey.shade400,
                        ),
                      )
                    else if (isMine && isLastMine && othersRead)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 2),
                        child: Text(
                          '已读',
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.grey.shade400),
                        ),
                      ),
                  ],
                ),
              ),
              if (isMine) const SizedBox(width: 4),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _videoBubble(BuildContext context, Message message) {
  final url = resolveUrl(context, message.content);
  return GestureDetector(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoViewerScreen(url: url)),
    ),
    child: Container(
      width: 200,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3F55), Color(0xFF16181F)],
        ),
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(Icons.play_circle_fill, size: 52, color: Colors.white70),
          ),
          Positioned(
            left: 10,
            bottom: 8,
            child: Row(
              children: const [
                Icon(Icons.videocam, size: 13, color: Colors.white70),
                SizedBox(width: 4),
                Text('视频',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 新消息入场动画（淡入 + 轻微上滑），仅新消息播放一次。
class _AnimatedAppear extends StatelessWidget {
  final bool play;
  final Widget child;

  const _AnimatedAppear({super.key, required this.play, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!play) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 12),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// "对方正在输入" 的三个跳动小点。
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '对方正在输入',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
        const SizedBox(width: 4),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final raw = (_c.value * 3 - i) % 3;
              final v = raw < 1 ? raw : (raw < 2 ? 2 - raw : 0.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Opacity(
                  opacity: 0.25 + 0.75 * v,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade500,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
