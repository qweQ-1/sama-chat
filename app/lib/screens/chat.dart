import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show openFile, XFile;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../image_utils.dart';
import '../models.dart';
import '../store.dart';
import '../voice_player.dart';
import '../widgets.dart';
import 'group_info.dart';
import 'favorites.dart';
import 'polls.dart';
import 'search.dart';
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
  Message? _replyTo; // 正在回复的消息
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
    _recordTimer?.cancel();
    _recorder?.dispose();
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
    final reply = _replyTo;
    _input.clear();
    setState(() => _replyTo = null);
    s.sendTyping(convId, false);
    _sentTypingFalse = true;
    try {
      if (reply != null) {
        await s.sendReply(convId, text, reply);
      } else {
        await s.sendText(convId, text);
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  /// 转发消息到其它会话（图片/视频/文件/语音/表情直接用原 URL）。
  Future<void> _forward(Message m) async {
    final s = context.read<AppState>();
    final target = await showModalBottomSheet<Conversation>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('转发到…',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            for (final c in s.conversations)
              if (c.id != m.conversationId)
                ListTile(
                  leading: Avatar(name: c.name, size: 40),
                  title: Text(c.isGroup ? '${c.name} (${c.memberCount})' : c.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(ctx, c),
                ),
            if (s.conversations.where((c) => c.id != m.conversationId).isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('没有其它会话可转发', textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await s.forwardMessage(target.id, m);
      if (mounted) showError(context, '已转发到「${target.name}」');
    } on ApiException catch (e) {
      if (mounted) showError(context, '转发失败：${e.message}');
    } catch (e) {
      if (mounted) showError(context, '转发失败：$e');
    }
  }

  /// 收藏一条消息（本地保存）。
  Future<void> _favorite(Message m) async {
    final s = context.read<AppState>();
    String convName = widget.conversation.name;
    for (final c in s.conversations) {
      if (c.id == m.conversationId) convName = c.name;
    }
    await Favorites.add(FavoriteItem(
      id: m.id,
      conversationName: convName,
      senderName: m.sender?.displayName ?? '',
      type: m.type,
      content: m.content,
      fileName: m.fileName,
      createdAt: m.createdAt,
    ));
    if (mounted) {
      showError(context, '已收藏 ⭐');
    }
  }

  /// 删除本地消息（仅从自己界面消失；重进会话也不会再出现）。
  Future<void> _confirmDeleteLocal(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('从自己的聊天界面删除这条消息？（对方不受影响）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    context.read<AppState>().deleteLocalMessage(m.conversationId, m.id);
  }

  // ---------------- 语音录制 ----------------
  AudioRecorder? _recorder;
  bool _recording = false;
  DateTime? _recordStart;
  Timer? _recordTimer;
  int _recordSecs = 0;

  Future<void> _startRecord() async {
    final s = context.read<AppState>();
    try {
      final rec = _recorder ??= AudioRecorder();
      if (!await rec.hasPermission()) {
        if (mounted) showError(context, '没有麦克风权限，请在系统设置里允许');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000), path: path);
      _recordStart = DateTime.now();
      _recordSecs = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSecs += 1);
        if (_recordSecs >= 60) _stopRecord(cancel: false);
      });
      if (mounted) setState(() => _recording = true);
      s.sendTyping(convId, false);
    } catch (e) {
      if (mounted) showError(context, '无法开始录音：$e');
    }
  }

  Future<void> _stopRecord({required bool cancel}) async {
    final s = context.read<AppState>();
    final rec = _recorder;
    _recordTimer?.cancel();
    _recordTimer = null;
    if (rec == null || !_recording) {
      if (mounted) setState(() => _recording = false);
      return;
    }
    setState(() => _recording = false);
    try {
      final path = await rec.stop();
      final secs = _recordStart == null
          ? _recordSecs
          : DateTime.now().difference(_recordStart!).inSeconds;
      _recordStart = null;
      if (cancel || path == null) return;
      if (secs < 1) {
        if (mounted) showError(context, '说话时间太短');
        return;
      }
      final f = File(path);
      final bytes = await f.readAsBytes();
      try {
        await f.delete();
      } catch (_) {}
      if (bytes.isEmpty) {
        if (mounted) showError(context, '录音失败，请重试');
        return;
      }
      await s.sendVoice(convId, bytes, 'm4a', secs.clamp(1, 60));
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '语音发送失败：$e');
    }
  }

  // ---------------- @提及 ----------------
  /// 在群里弹出成员列表，选中后把「@昵称 」插入输入框。
  Future<void> _mention() async {
    final s = context.read<AppState>();
    try {
      final (_, members) = await s.api.groupMembers(convId);
      if (!mounted) return;
      final meId = s.me?.id;
      final pick = await showModalBottomSheet<GroupMember>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text('@ 谁',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              for (final m in members)
                if (m.user.id != meId)
                  ListTile(
                    leading: Avatar(name: m.user.displayName, url: m.user.avatar, size: 38),
                    title: Text(m.user.displayName),
                    subtitle: m.isOwner
                        ? const Text('群主', style: TextStyle(fontSize: 11))
                        : null,
                    onTap: () => Navigator.pop(ctx, m),
                  ),
            ],
          ),
        ),
      );
      if (pick == null || !mounted) return;
      _insertEmoji('@${pick.user.displayName} ');
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

  /// 打开文件：下载到临时目录再交给系统打开。
  Future<void> _openFile(Message m) async {
    try {
      final base = context.read<AppState>().serverBase;
      final full = m.content.startsWith('http') ? m.content : '$base${m.content}';
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(full));
      final res = await req.close();
      final dir = await getTemporaryDirectory();
      final safeName = m.fileName.isEmpty ? 'file_${m.id}' : m.fileName;
      final f = File('${dir.path}/$safeName');
      final sink = f.openWrite();
      await res.pipe(sink);
      await sink.close();
      client.close();
      await OpenFilex.open(f.path);
    } catch (e) {
      if (mounted) showError(context, '文件打开失败：$e');
    }
  }

  /// 发起语音通话（仅私聊可用）。
  Future<void> _startCall(BuildContext context) async {
    final s = context.read<AppState>();
    final me = s.me;
    if (me == null) return;
    final otherId =
        widget.conversation.memberIds.firstWhere((m) => m != me.id, orElse: () => '');
    User? peer;
    for (final f in s.friends) {
      if (f.id == otherId) {
        peer = f;
        break;
      }
    }
    if (peer == null) {
      showError(context, '只有好友之间才能通话');
      return;
    }
    try {
      await s.startCall(peer);
    } catch (e) {
      if (mounted) showError(context, '呼叫失败：$e');
    }
  }

  Future<void> _sendImage() async {
    final s = context.read<AppState>();
    try {
      // 注意：不能传 maxWidth/imageQuality，否则 image_picker 会把 GIF 重编码成静图
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;
      setState(() => _sendingMedia = true);
      final raw = await x.readAsBytes();
      final ext0 = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : 'jpg';
      // GIF 动图必须原样上传：压缩或缩放都会把动画变成静态图
      final img = isAnimatedGif(raw, ext0)
          ? (bytes: raw, ext: 'gif')
          : await compressImage(raw, fallbackExt: ext0);
      if (img.bytes.length > kMaxUploadBytes) {
        if (mounted) showError(context, '图片太大了（限 6MB），GIF 动图请选小一点的');
        return;
      }
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
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('文件'),
              subtitle: const Text('任何类型文件 · 限 25MB',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'file'),
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
    } else if (choice == 'file') {
      await _sendFile();
    }
  }

  /// 选文件并发送（任意类型，限 25MB）。
  Future<void> _sendFile() async {
    final s = context.read<AppState>();
    try {
      final XFile? f = await openFile();
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) {
        if (mounted) showError(context, '文件过大（限 25MB）');
        return;
      }
      setState(() => _sendingMedia = true);
      await s.sendFile(convId, bytes, f.name);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发送失败：$e');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
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
        actions: [
          if (!widget.conversation.isGroup)
            IconButton(
              tooltip: '语音通话',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => _startCall(context),
            ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          if (widget.conversation.isGroup)
            IconButton(
              tooltip: '群投票',
              icon: const Icon(Icons.how_to_vote_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PollsScreen(conversation: _currentConv(s)),
                ),
              ),
            ),
        ],
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
                                myId: me?.id,
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
                                onReply: () => setState(() => _replyTo = m),
                                onForward: () => _forward(m),
                                onDelete: m.senderId == me?.id && !m.pending
                                    ? () => _confirmDeleteLocal(m)
                                    : null,
                                onOpenFile:
                                    m.isFile ? () => _openFile(m) : null,
                                onFavorite: () => _favorite(m),
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
                if (_replyTo != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    color: Theme.of(context).colorScheme.surface,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '回复 ${_replyTo!.sender?.displayName ?? ''}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                _replyTo!.recalled
                                    ? '[已撤回]'
                                    : _replyTo!.isVoice
                                        ? '[语音]'
                                        : _replyTo!.isImage
                                            ? '[图片]'
                                            : _replyTo!.isVideo
                                                ? '[视频]'
                                                : _replyTo!.isFile
                                                    ? '[文件]'
                                                    : _replyTo!.isSticker
                                                        ? '[表情]'
                                                        : _replyTo!.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _replyTo = null),
                        ),
                      ],
                    ),
                  ),
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
            recording: _recording,
            recordSecs: _recordSecs,
            onStartRecord: (Platform.isAndroid || Platform.isIOS)
                ? _startRecord
                : null,
            onStopRecord: () => _stopRecord(cancel: false),
            onMention: widget.conversation.isGroup ? _mention : null,
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
  final bool recording;
  final int recordSecs;
  final VoidCallback? onStartRecord;
  final VoidCallback? onStopRecord;
  final VoidCallback? onMention;

  const _InputBar({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
    required this.sendingMedia,
    required this.panelOpen,
    required this.onToggleEmoji,
    required this.onFieldTap,
    this.recording = false,
    this.recordSecs = 0,
    this.onStartRecord,
    this.onStopRecord,
    this.onMention,
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
            // 语音按钮（移动端）——点一下开始录音，再点发送
            if (onStartRecord != null && !recording)
              IconButton(
                tooltip: '发语音',
                onPressed: sendingMedia ? null : onStartRecord,
                icon: const Icon(Icons.mic_none_outlined),
              ),
            // @提及（仅群聊显示）
            if (onMention != null && !recording)
              IconButton(
                tooltip: '@群成员',
                onPressed: sendingMedia ? null : onMention,
                icon: const Icon(Icons.alternate_email, size: 20),
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
            if (!recording)
              IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded, size: 20),
              ),
            // 录音状态：显示计时 + 松手发送按钮
            if (recording)
              FilledButton.icon(
                onPressed: onStopRecord,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                icon: const Icon(Icons.stop, size: 16),
                label: Text('${recordSecs}s 发送'),
              ),
          ],
        ),
      );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final String? myId;
  bool get isMine => message.senderId == myId;
  final bool isGroup;
  final bool showTime;
  final bool isLastMine;
  final bool othersRead;
  final bool canRecall;
  final VoidCallback? onRecall;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenFile;
  final VoidCallback? onFavorite;

  const _Bubble({
    required this.message,
    required this.myId,
    required this.isGroup,
    required this.showTime,
    required this.isLastMine,
    required this.othersRead,
    this.canRecall = false,
    this.onRecall,
    this.onReply,
    this.onForward,
    this.onDelete,
    this.onOpenFile,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final senderName = message.sender?.displayName ?? '';

    if (message.recalled) {      return Padding(
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

    Widget content = message.isVoice
        ? VoiceBubble(
            url: message.content,
            duration: message.duration,
            isMine: isMine,
          )
        : message.isFile
        ? _fileBubble(context)
        : message.isVideo
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

    if (message.isFile) {
      content = GestureDetector(onTap: onOpenFile, child: content);
    }

    // 引用回复：显示引用块。
    if (message.replyToId.isNotEmpty && !message.recalled) {
      content = Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 220),
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                    color: Theme.of(context).colorScheme.primary, width: 2.5),
              ),
            ),
            child: Text(
              message.replyPreview.isEmpty ? '[引用]' : message.replyPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
          content,
        ],
      );
    }

    if (!message.recalled && !message.pending && !message.failed &&
        (onReply != null || onForward != null || onRecall != null || onDelete != null)) {
      content = GestureDetector(
        onLongPress: () => _showMessageMenu(context),
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

  /// 文件消息气泡：图标 + 文件名 + 大小 + 打开提示。
  Widget _fileBubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = isMine ? Colors.white : scheme.onSurface;
    final sizeText = message.fileSize > 0
        ? _fmtSize(message.fileSize)
        : '';
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMine
            ? scheme.primary
            : (Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : scheme.surfaceContainerHighest),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
        boxShadow: isMine
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: fg, size: 30),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.fileName.isEmpty ? '文件' : message.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  sizeText.isEmpty ? '点击打开' : '$sizeText · 点击打开',
                  style: TextStyle(
                      color: fg.withValues(alpha: 0.7), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  /// 长按消息菜单：回复 / 转发 / 撤回 / 删除。
  void _showMessageMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('回复'),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply!();
                },
              ),
            if (onForward != null)
              ListTile(
                leading: const Icon(Icons.forward_outlined),
                title: const Text('转发'),
                onTap: () {
                  Navigator.pop(ctx);
                  onForward!();
                },
              ),
            if (onFavorite != null)
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('收藏'),
                onTap: () {
                  Navigator.pop(ctx);
                  onFavorite!();
                },
              ),
            if (canRecall && onRecall != null)
              ListTile(
                leading: const Icon(Icons.undo_outlined),
                title: const Text('撤回'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRecall!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                title: const Text('删除',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
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
