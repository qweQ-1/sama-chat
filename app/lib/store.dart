/// Central app state: auth, conversations, messages, moments.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'keepalive.dart';
import 'models.dart';
import 'notifications.dart';
import 'realtime.dart';

/// 已保存的账号（「切换账号」用；无需重新输密码）。
class SavedAccount {
  final String id; // 用户 id
  final String token;
  final String displayName;
  final String username;
  final String? avatar;
  final String email;
  final String phone;
  final String serverBase;

  SavedAccount({
    required this.id,
    required this.token,
    required this.displayName,
    required this.username,
    this.avatar,
    this.email = '',
    this.phone = '',
    required this.serverBase,
  });

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
        id: j['id'] as String? ?? '',
        token: j['token'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatar: j['avatar'] as String?,
        email: j['email'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        serverBase: j['serverBase'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'token': token,
        'displayName': displayName,
        'username': username,
        'avatar': avatar,
        'email': email,
        'phone': phone,
        'serverBase': serverBase,
      };

  /// 账号标识（邮箱 > 手机号 > @用户名），用于列表展示。
  String get ident =>
      email.isNotEmpty ? email : (phone.isNotEmpty ? phone : '@$username');
}

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

  /// 已保存的账号（「切换账号」用）。
  List<SavedAccount> savedAccounts = [];

  /// 未读公告（弹过一次后清空并上报已读）。
  List<Announcement> pendingAnnouncements = [];
  bool announcementShown = false; // 弹窗防重入
  final Set<String> _ackedAnnIds = {};

  /// 是否有发布公告权限（huzhi 账号，服务端下发）。
  bool canAnnounce = false;

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
    _loadSavedAccounts();
    unawaited(_syncServerTime());
    token = _prefs!.getString('token');
    if (token != null && token!.isNotEmpty) {
      api.token = token;
      try {
        me = await api.me();
        canAnnounce = me?.canAnnounce ?? false;
        _afterLogin();
        unawaited(_rememberAccount());
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
  Future<void> register({
    String? username,
    required String password,
    String? displayName,
    String? phone,
    String? email,
    String? code,
  }) async {
    final (t, user) = await api.register(
      username: username,
      password: password,
      displayName: displayName,
      phone: phone,
      email: email,
      code: code,
    );
    await _saveSession(t, user);
  }

  /// 登录第一步：查手机号/邮箱名下的所有账号。
  Future<List<User>> accounts({String? phone, String? email}) =>
      api.accounts(phone: phone, email: email);

  /// 发送短信验证码（mode: sent/dev/console）。
  Future<({String mode, String? devCode})> sendSmsCode(String phone) =>
      api.sendSmsCode(phone);

  /// 发送邮箱验证码（mode: sent/dev/console）。
  Future<({String mode, String? devCode})> sendEmailCode(String email) =>
      api.sendEmailCode(email);

  /// 服务器当前注册模式（email / phone）。
  Future<String> fetchAuthMode() => api.fetchAuthMode();

  /// 绑定 / 修改绑定的手机号（需短信验证码）。
  Future<void> bindPhone(String phone, String code) async {
    me = await api.updateMe(phone: phone, code: code);
    notifyListeners();
  }

  /// 绑定 / 修改绑定的邮箱（需邮箱验证码）。
  Future<void> bindEmail(String email, String code) async {
    me = await api.updateMe(email: email, code: code);
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final (t, user) = await api.login(username, password);
    await _saveSession(t, user);
  }

  Future<void> _saveSession(String t, User user) async {
    token = t;
    api.token = t;
    me = user;
    canAnnounce = user.canAnnounce;
    await _prefs?.setString('token', t);
    await _rememberAccount();
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
    unawaited(checkAnnouncements());
    notifyListeners();
  }

  Future<void> logout() async {
    rt.disconnect();
    unawaited(KeepAliveService.stop());
    token = null;
    api.token = null;
    me = null;
    canAnnounce = false;
    _resetData();
    await _prefs?.remove('token');
    notifyListeners();
  }

  /// 清空当前账号的运行数据（切号 / 退出时用；已保存的账号列表不受影响）。
  void _resetData() {
    conversations = [];
    chatMessages.clear();
    friends = [];
    incomingRequests = [];
    moments = [];
    onlineUserIds.clear();
    typingIn.clear();
    rtConnected = false;
    activeChatId = null;
    pendingAnnouncements = [];
    _ackedAnnIds.clear();
    announcementShown = false;
  }

  // ---------------------------------------------------------- 多账号切换
  void _loadSavedAccounts() {
    try {
      final raw = _prefs?.getString('savedAccounts');
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => SavedAccount.fromJson(e.cast<String, dynamic>()))
          .where((a) => a.id.isNotEmpty && a.token.isNotEmpty)
          .toList();
      savedAccounts = list;
    } catch (_) {}
  }

  Future<void> _saveSavedAccounts() async {
    try {
      await _prefs?.setString('savedAccounts',
          jsonEncode(savedAccounts.map((a) => a.toJson()).toList()));
    } catch (_) {}
  }

  /// 把当前登录的账号记入「已保存账号」列表（最近的排最前）。
  Future<void> _rememberAccount() async {
    final u = me;
    final t = token;
    if (u == null || t == null) return;
    final acc = SavedAccount(
      id: u.id,
      token: t,
      displayName: u.displayName,
      username: u.username,
      avatar: u.avatar,
      email: u.email,
      phone: u.phone,
      serverBase: serverBase,
    );
    savedAccounts.removeWhere((a) => a.id == acc.id);
    savedAccounts.insert(0, acc);
    await _saveSavedAccounts();
    notifyListeners();
  }

  /// 切换到另一个已保存的账号。先验证该账号 token 有效，成功才原子切换；
  /// 失败不会破坏当前会话（直接抛错给界面提示）。
  Future<void> switchAccount(String id) async {
    if (me?.id == id) return;
    final acc = savedAccounts.firstWhere(
      (a) => a.id == id,
      orElse: () => throw ApiException(404, '账号不存在'),
    );
    // 1) 用独立的 Api 实例验证（不动当前状态）
    final base = acc.serverBase.isNotEmpty ? acc.serverBase : serverBase;
    final probe = Api(base)..token = acc.token;
    final User user = await probe.me();

    // 2) 原子切换
    rt.disconnect();
    _resetData();
    serverBase = base;
    api.base = base;
    token = acc.token;
    api.token = acc.token;
    me = user;
    canAnnounce = user.canAnnounce;
    await _prefs?.setString('serverBase', base);
    await _prefs?.setString('token', acc.token);
    await _rememberAccount();
    unawaited(_syncServerTime());
    _afterLogin();
    notifyListeners();
  }

  /// 从「已保存账号」中删除一个账号；删的是当前账号时自动切走或退出登录。
  Future<void> removeAccount(String id) async {
    savedAccounts.removeWhere((a) => a.id == id);
    await _saveSavedAccounts();
    notifyListeners();
    if (me?.id != id) return;
    if (savedAccounts.isEmpty) {
      await logout();
      return;
    }
    try {
      await switchAccount(savedAccounts.first.id);
    } catch (_) {
      await logout();
    }
  }

  // ------------------------------------------------------------- 公告
  /// 拉取未读公告（登录 / 启动时调用；弹过后由 ackAnnouncements 标记已读）。
  Future<void> checkAnnouncements() async {
    try {
      final list = await api.unreadAnnouncements();
      if (list.isEmpty) return;
      var changed = false;
      for (final a in list) {
        if (_ackedAnnIds.contains(a.id)) continue;
        if (pendingAnnouncements.any((x) => x.id == a.id)) continue;
        pendingAnnouncements.add(a);
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  /// 标记全部待弹公告为已读（保证「只弹一次」）。
  Future<void> ackAnnouncements() async {
    final ids = pendingAnnouncements.map((a) => a.id).toList();
    if (ids.isEmpty) return;
    _ackedAnnIds.addAll(ids);
    pendingAnnouncements = [];
    notifyListeners();
    try {
      await api.ackAnnouncements(ids);
    } catch (_) {}
  }

  /// 发布公告（服务端强校验权限，失败抛 ApiException）。
  Future<void> publishAnnouncement(String content) async {
    await api.publishAnnouncement(content);
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
    final body = msg.isSticker
        ? '[表情]'
        : (msg.isImage ? '[图片]' : (msg.isVideo ? '[视频]' : msg.content));
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
      case 'announce:new':
        if (data is Map && data['announcement'] is Map) {
          final a = Announcement.fromJson(
              (data['announcement'] as Map).cast<String, dynamic>());
          if (!_ackedAnnIds.contains(a.id) &&
              !pendingAnnouncements.any((x) => x.id == a.id)) {
            pendingAnnouncements.add(a);
            notifyListeners();
          }
        }
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

  /// 发送自定义表情（小图；以 sticker 类型发出，对方以小号展示）。
  Future<Message> sendSticker(String conversationId, Uint8List bytes, String ext) async {
    final url = await api.uploadImage(bytes, _normExt(ext));
    return sendStickerUrl(conversationId, url);
  }

  /// 发送已在服务器上的表情（表情商店里下载的表情包图片，无需重复上传）。
  Future<Message> sendStickerUrl(String conversationId, String url) async {
    final msg = await api.sendMessage(conversationId, content: url, type: 'sticker');
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
