/// Central app state: auth, conversations, messages, moments.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';
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

  // ---------------------------------------------------------------- boot
  Future<void> boot() async {
    rt.events.listen(_onRealtimeEvent);
    _prefs = await SharedPreferences.getInstance();
    serverBase = _prefs!.getString('serverBase') ?? AppConfig.defaultServer;
    api.base = serverBase;
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
    _afterLogin();
    notifyListeners();
  }

  void _afterLogin() {
    _connectRealtime();
    unawaited(refreshConversations());
    unawaited(refreshFriends());
    unawaited(refreshRequests());
    unawaited(refreshMoments());
    notifyListeners();
  }

  Future<void> logout() async {
    rt.disconnect();
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
      case 'message:new':
        if (data is Map) {
          _appendMessage(
              Message.fromJson((data['message'] as Map).cast<String, dynamic>()));
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
        unawaited(refreshRequests());
      case 'friend:accepted':
        unawaited(refreshFriends());
        unawaited(refreshRequests());
      case 'conversation:new':
      case 'conversation:update':
        unawaited(refreshConversations());
      case 'moment:new':
        unawaited(refreshMoments());
    }
  }

  void _appendMessage(Message msg) {
    final list = chatMessages.putIfAbsent(msg.conversationId, () => []);
    if (list.any((m) => m.id == msg.id)) return; // dedupe REST echo
    list.add(msg);

    final idx = conversations.indexWhere((c) => c.id == msg.conversationId);
    if (idx >= 0) {
      final c = conversations[idx];
      final isMine = msg.senderId == me?.id;
      final isActive = activeChatId == msg.conversationId;
      conversations[idx] = c.copyWith(
        lastMessage: msg,
        unread: isMine || isActive ? c.unread : c.unread + 1,
      );
      _sortConversations();
    } else {
      unawaited(refreshConversations());
    }
    notifyListeners();
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
  Future<Message> sendText(String conversationId, String text) async {
    final msg = await api.sendMessage(conversationId, text: text);
    _appendMessage(msg);
    return msg;
  }

  Future<Message> sendImage(String conversationId, Uint8List bytes, String ext) async {
    final url = await api.uploadImage(bytes, _normExt(ext));
    final msg = await api.sendMessage(conversationId, content: url, type: 'image');
    _appendMessage(msg);
    return msg;
  }

  void sendTyping(String conversationId, bool typing) {
    rt.send('typing', {'conversationId': conversationId, 'typing': typing});
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

  String _normExt(String ext) {
    final e = ext.toLowerCase().replaceAll('.', '');
    const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    return allowed.contains(e) ? e : 'jpg';
  }
}
