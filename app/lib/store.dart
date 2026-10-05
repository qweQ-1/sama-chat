/// Central app state: auth, conversations, messages, moments.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'keepalive.dart';
import 'models.dart';
import 'notifications.dart';
import 'realtime.dart';

class AppState extends ChangeNotifier {
  final Api api = Api(AppConfig.defaultServer);
  final Realtime rt = Realtime();

  SharedPreferences? _prefs;
  bool booted = false;

  String serverBase = AppConfig.defaultServer;
  String? token;
  User? me;

  List<Conversation> conversations = [];
  final Map<String, List<Message>> chatMessages = {};
  List<User> friends = [];
  List<FriendRequest> incomingRequests = [];
  List<Moment> moments = [];

  final Set<String> onlineUserIds = {};
  final Map<String, Set<String>> typingIn = {};
  bool rtConnected = false;

  /// Conversation currently open on screen (suppresses unread badge).
  String? activeChatId;

  /// 消息通知 / 后台保活开关（「我 → 设置」里可改）。
  bool notificationsEnabled = true;
  bool keepAliveEnabled = true;
  bool appInForeground = true;

  /// 诊断用：最近一次收到消息的时间。
  DateTime? lastMessageAt;

  // ---------------------------------------------------------------- boot
  Future<void> boot() async {
    rt.events.listen(_onRealtimeEvent);
    _prefs = await SharedPreferences.getInstance();
    serverBase = _prefs!.getString('serverBase') ?? AppConfig.defaultServer;
    api.base = serverBase;
    notificationsEnabled = _prefs!.getBool('notifications') ?? true;
    keepAliveEnabled = _prefs!.getBool('keepAlive') ?? true;
    unawaited(_syncServerTime());
    token = _prefs!.getString('token');
    if (token != null && token!.isNotEmpty) {
      api.token = token;
      try {
        me = await api.me();
        _afterLogin();
      } catch (_) {
        // token invalid or server unreachable — keep it; user can re-login
        token = null;
        api.token = null;
        await _prefs!.remove('token');
      }
    }
    booted = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- auth
  Future<void> register(String username, String password, String displayName) async {
    final (t, user) = await api.register(username, password, displayName);
    await _saveSession(t, user);
  }

  Future<void> login(String username, String password) async {
    final (t, user) = await api.login(username, password);
    await _saveSession(t, user);
  }

  Future<void> _saveSession(String t, User user) async {
    token = t;
    api.token = t;
    me = user;
    await _prefs?.setString('token', t);
    unawaited(_syncServerTime());
    _afterLogin();
    notifyListeners();
  }

  /// 以服务器时间为准（防止设备时钟不准导致撤回/新鲜度判断出错）。
  Future<void> _syncServerTime() async {
    try {
      final before = DateTime.now().millisecondsSinceEpoch;
      final serverMs = await api.serverTime();
      final after = DateTime.now().millisecondsSinceEpoch;
      serverTimeOffsetMs = serverMs - ((before + after) ~/ 2);
    } catch (_) {}
  }

  void _afterLogin() {
    _connectRealtime();
    unawaited(AppNotifications.init());
    if (notificationsEnabled) {
      unawaited(AppNotifications.requestPermissions());
    }
    if (keepAliveEnabled) {
      unawaited(KeepAliveService.start());
    }
    unawaited(refreshConversations());
    unawaited(refreshFriends());
    unawaited(refreshRequests());
    unawaited(refreshMoments());
    notifyListeners();
  }

  Future<void> logout() async {
    rt.disconnect();
    unawaited(KeepAliveService.stop());
    token = null;
    api.token = null;
    me = null;
    conversations = [];
    chatMessages.clear();
    friends = [];
    incomingRequests = [];
    moments = [];
    onlineUserIds.clear();
    typingIn.clear();
    rtConnected = false;
    await _prefs?.remove('token');
    notifyListeners();
  }

  Future<void> updateProfile({String? displayName, String? avatar}) async {
    me = await api.updateMe(displayName: displayName, avatar: avatar);
    notifyListeners();
  }

  // ---------------------------------------------------------- 通知 / 保活
  Future<void> setNotifications(bool v) async {
    notificationsEnabled = v;
    if (v) unawaited(AppNotifications.requestPermissions());
    await _prefs?.setBool('notifications', v);
    notifyListeners();
  }

  Future<void> setKeepAlive(bool v) async {
    keepAliveEnabled = v;
    if (v) {
      unawaited(KeepAliveService.start());
    } else {
      unawaited(KeepAliveService.stop());
    }
    await _prefs?.setBool('keepAlive', v);
    notifyListeners();
  }

  /// App 回到前台。
  void handleResume() {
    appInForeground = true;
    rt.ensureConnected();
    unawaited(_syncServerTime());
    if (keepAliveEnabled) unawaited(KeepAliveService.start());
  }

  /// App 退到后台。
  void handleBackground() {
    appInForeground = false;
  }

  void _maybeNotifyMessage(Message msg) {
    if (!notificationsEnabled) return;
    if (msg.senderId == me?.id) return;
    if (activeChatId == msg.conversationId && appInForeground) return;
    var title = msg.sender?.displayName ?? '新消息';
    for (final c in conversations) {
      if (c.id == msg.conversationId) {
        if (c.isGroup) title = c.name;
        break;
      }
    }
    final body = msg.isImage ? '[图片]' : (msg.isVideo ? '[视频]' : msg.content);
    unawaited(AppNotifications.showMessage(
      title: title,
      body: body,
      id: msg.conversationId.hashCode & 0x7fffffff,
    ));
  }

  /// Change the server address (e.g. after deploying). Logs the user out.
  Future<void> setServer(String url) async {
    var clean = url.trim();
    if (clean.isEmpty) return;
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    serverBase = clean;
    api.base = clean;
    await _prefs?.setString('serverBase', clean);
    await logout();
  }

  // ------------------------------------------------------------- realtime
  void _connectRealtime() {
    final t = token;
    if (t == null) return;
    rt.connect(serverBase, t).then((_) {
      rtConnected = rt.connected;
      notifyListeners();
    });
  }

  void _onRealtimeEvent(Map<String, dynamic> m) {
    final event = m['event'] as String?;
    final data = m['data'];
    switch (event) {
      case 'connected':
        rtConnected = true;
        notifyListeners();
      case 'message:recalled':
        if (data is Map) {
          final convId = data['conversationId'] as String?;
          final mid = data['messageId'] as String?;
          if (convId != null && mid != null) {
            _markRecalled(convId, mid);
            unawaited(refreshConversations());
          }
        }
      case 'rt:state':
        if (data is Map) {
          rtConnected = data['connected'] as bool? ?? false;
          if (rtConnected) unawaited(refreshConversations());
          notifyListeners();
        }
      case 'message:new':
        if (data is Map) {
          final msg =
              Message.fromJson((data['message'] as Map).cast<String, dynamic>());
          _appendMessage(msg);
          _maybeNotifyMessage(msg);
        }
      case 'typing':
        if (data is Map) {
          final convId = data['conversationId'] as String?;
          final uid = data['userId'] as String?;
          final typing = data['typing'] as bool? ?? false;
          if (convId != null && uid != null) {
            final set = typingIn.putIfAbsent(convId, () => {});
            typing ? set.add(uid) : set.remove(uid);
            notifyListeners();
          }
        }
      case 'message:read':
        if (data is Map) {
          final convId = data['conversationId'] as String?;
          final uid = data['userId'] as String?;
          if (convId != null && uid != null) {
            final list = chatMessages[convId];
            if (list != null) {
              for (var i = 0; i < list.length; i++) {
                final msg = list[i];
                if (msg.senderId != uid && !msg.readBy.contains(uid)) {
                  list[i] = Message(
                    id: msg.id,
                    conversationId: msg.conversationId,
                    senderId: msg.senderId,
                    type: msg.type,
                    content: msg.content,
                    createdAt: msg.createdAt,
                    readBy: [...msg.readBy, uid],
                    sender: msg.sender,
                  );
                }
              }
            }
            notifyListeners();
          }
        }
      case 'presence:update':
        if (data is Map) {
          final uid = data['userId'] as String?;
          final online = data['online'] as bool? ?? false;
          if (uid != null) {
            online ? onlineUserIds.add(uid) : onlineUserIds.remove(uid);
            notifyListeners();
          }
        }
      case 'friend:request':
        if (notificationsEnabled) {
          final from = (data is Map && data['from'] is Map)
              ? User.fromJson((data['from'] as Map).cast<String, dynamic>())
              : null;
          unawaited(AppNotifications.showMessage(
            title: '新的好友请求',
            body: '${from?.displayName ?? '有人'} 想加你为好友',
            id: 900001,
          ));
        }
        unawaited(refreshRequests());
      case 'friend:removed':
        unawaited(refreshFriends());
        unawaited(refreshConversations());
      case 'friend:accepted':
        unawaited(refreshFriends());
        unawaited(refreshRequests());
      case 'conversation:new':
      case 'conversation:update':
        unawaited(refreshConversations());
      case 'moment:new':
        unawaited(refreshMoments());
      case 'moment:deleted':
        if (data is Map) {
          final mid = data['momentId'] as String?;
          if (mid != null) {
            moments = moments.where((m) => m.id != mid).toList();
            notifyListeners();
          }
        }
    }
  }

  void _appendMessage(Message msg) {
    final list = chatMessages.putIfAbsent(msg.conversationId, () => []);
    if (list.any((m) => m.id == msg.id)) return; // dedupe REST echo

    // 服务器回显替换本地乐观消息（同发送者、同内容、短时间内）
    final tIdx = list.indexWhere((m) =>
        m.id.startsWith('tmp_') &&
        m.pending &&
        m.senderId == msg.senderId &&
        m.content == msg.content &&
        (msg.createdAt - m.createdAt).abs() < 60000);
    if (tIdx >= 0) {
      list[tIdx] = msg;
      _updatePreview(msg.conversationId, msg);
      notifyListeners();
      return;
    }

    list.add(msg);
    lastMessageAt = DateTime.now();
    _updatePreview(msg.conversationId, msg);
    notifyListeners();
  }

  void _updatePreview(String conversationId, Message msg) {
    final idx = conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      final c = conversations[idx];
      final isMine = msg.senderId == me?.id;
      final isActive = activeChatId == conversationId;
      conversations[idx] = c.copyWith(
        lastMessage: msg,
        unread: isMine || isActive ? c.unread : c.unread + 1,
      );
      _sortConversations();
    } else {
      unawaited(refreshConversations());
    }
  }

  void _sortConversations() {
    conversations.sort((a, b) =>
        (b.lastMessage?.createdAt ?? 0).compareTo(a.lastMessage?.createdAt ?? 0));
  }

  // -------------------------------------------------------- data refresh
  Future<void> refreshConversations() async {
    try {
      conversations = await api.conversations();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshFriends() async {
    try {
      friends = await api.friends();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshRequests() async {
    try {
      final r = await api.friendRequests();
      incomingRequests = r.incoming;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshMoments() async {
    try {
      moments = await api.moments();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadMessages(String conversationId) async {
    final list = await api.messages(conversationId);
    chatMessages[conversationId] = list;
    notifyListeners();
  }

  Future<void> markConversationRead(String conversationId) async {
    rt.send('message:read', {'conversationId': conversationId});
    final idx = conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0 && conversations[idx].unread > 0) {
      conversations[idx] = conversations[idx].copyWith(unread: 0);
      notifyListeners();
    }
    try {
      await api.markRead(conversationId);
    } catch (_) {}
  }

  // ------------------------------------------------------------- talking
  /// 发送文字：先本地立即上屏（乐观更新），服务器确认后替换为正式消息。
  Future<void> sendText(String conversationId, String text) async {
    final meId = me?.id ?? '';
    final nowMsVal = serverNowMs();
    final temp = Message(
      id: 'tmp_${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: meId,
      type: 'text',
      content: text,
      createdAt: nowMsVal,
      readBy: [meId],
      sender: me,
      pending: true,
    );
    _appendMessage(temp);
    try {
      final msg = await api.sendMessage(conversationId, text: text);
      _replaceLocal(temp.id, msg);
    } catch (_) {
      _markFailed(temp.id);
      rethrow;
    }
  }

  void _replaceLocal(String tempId, Message real) {
    final list = chatMessages[real.conversationId];
    if (list != null) {
      final idx = list.indexWhere((m) => m.id == tempId);
      if (idx >= 0) {
        list[idx] = real;
      } else if (!list.any((m) => m.id == real.id)) {
        list.add(real);
      }
    }
    _updatePreview(real.conversationId, real);
    notifyListeners();
  }

  void _markFailed(String tempId) {
    for (final list in chatMessages.values) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == tempId) {
          list[i] = list[i].copyWith(pending: false, failed: true);
        }
      }
    }
    notifyListeners();
  }

  Future<Message> sendImage(String conversationId, Uint8List bytes, String ext) async {
    final url = await api.uploadImage(bytes, _normExt(ext));
    final msg = await api.sendMessage(conversationId, content: url, type: 'image');
    _appendMessage(msg);
    return msg;
  }

  /// 发送视频（原始二进制上传 → 消息类型 video）。
  Future<Message> sendVideo(String conversationId, Uint8List bytes, String ext) async {
    final url = await api.uploadVideo(bytes, _normVideoExt(ext));
    final msg = await api.sendMessage(conversationId, content: url, type: 'video');
    _appendMessage(msg);
    return msg;
  }

  void sendTyping(String conversationId, bool typing) {
    rt.send('typing', {'conversationId': conversationId, 'typing': typing});
  }

  /// 撤回一条自己发的消息（5 分钟内）。
  Future<void> recallMessage(String conversationId, String messageId) async {
    await api.recallMessage(conversationId, messageId);
    _markRecalled(conversationId, messageId);
    unawaited(refreshConversations());
  }

  void _markRecalled(String conversationId, String messageId) {
    final list = chatMessages[conversationId];
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == messageId && !list[i].recalled) {
          list[i] = list[i].copyWith(recalled: true, content: '');
        }
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- friends
  Future<Conversation> openPrivateChat(User other) async {
    final c = await api.openPrivateConversation(other.id);
    final conv = Conversation(
      id: c.id,
      type: 'private',
      name: other.displayName,
      memberIds: c.memberIds,
      memberCount: c.memberIds.length,
    );
    await refreshConversations();
    return conv;
  }

  Future<Conversation> createGroup(String name, List<String> memberIds) async {
    final conv = await api.createGroup(name, memberIds);
    await refreshConversations();
    return conv;
  }

  // ------------------------------------------------------------- moments
  Future<void> publishMoment(String text, List<({Uint8List bytes, String ext})> images) async {
    final urls = <String>[];
    for (final img in images) {
      urls.add(await api.uploadImage(img.bytes, _normExt(img.ext)));
    }
    await api.postMoment(text, urls);
    await refreshMoments();
  }

  Future<void> toggleLike(String momentId) async {
    final idx = moments.indexWhere((m) => m.id == momentId);
    if (idx < 0) return;
    // optimistic flip
    final m = moments[idx];
    moments[idx] = m.copyWith(
      likedByMe: !m.likedByMe,
      likeCount: m.likeCount + (m.likedByMe ? -1 : 1),
    );
    notifyListeners();
    try {
      final (liked, count) = await api.likeMoment(momentId);
      moments[idx] = moments[idx].copyWith(likedByMe: liked, likeCount: count);
      notifyListeners();
    } catch (_) {
      moments[idx] = m; // rollback
      notifyListeners();
    }
  }

  Future<void> addComment(String momentId, String text) async {
    final comment = await api.commentMoment(momentId, text);
    final idx = moments.indexWhere((m) => m.id == momentId);
    if (idx >= 0) {
      moments[idx] = moments[idx]
          .copyWith(comments: [...moments[idx].comments, comment]);
      notifyListeners();
    }
  }

  /// 删除自己的炫圈（发布 2 分钟内；服务端校验）。
  Future<void> deleteMoment(String momentId) async {
    await api.deleteMoment(momentId);
    moments = moments.where((m) => m.id != momentId).toList();
    notifyListeners();
  }

  String _normExt(String ext) {
    final e = ext.toLowerCase().replaceAll('.', '');
    const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    return allowed.contains(e) ? e : 'jpg';
  }

  String _normVideoExt(String ext) {
    final e = ext.toLowerCase().replaceAll('.', '');
    const allowed = {'mp4', 'mov', 'm4v', 'webm'};
    return allowed.contains(e) ? e : 'mp4';
  }
}
