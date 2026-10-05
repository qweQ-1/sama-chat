/// REST client for the sama-chat server.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  String base;
  String? token;

  /// 持久 HTTP 客户端：复用 TCP+TLS 连接，避免每次请求重新握手（延迟大头）。
  final http.Client _client = http.Client();

  Api(this.base);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        // 保险：ngrok 免费版对"浏览器特征"的请求会弹警告页，带上这个头可跳过
        'ngrok-skip-browser-warning': '1',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _req(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$base$path');
    late http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await _client.get(uri, headers: _headers);
        case 'POST':
          res = await _client.post(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
        case 'PATCH':
          res = await _client.patch(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
        case 'DELETE':
          res = await _client.delete(uri, headers: _headers);
        default:
          throw ApiException(0, '不支持的请求方法');
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(0, '网络连接失败，请检查服务器地址');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode,
          json['message'] as String? ?? '请求失败 (${res.statusCode})');
    }
    return json;
  }

  // ---------- auth ----------
  Future<(String, User)> register(String username, String password, String displayName) async {
    final j = await _req('POST', '/auth/register',
        body: {'username': username, 'password': password, 'displayName': displayName}, auth: false);
    return (j['token'] as String, User.fromJson((j['user'] as Map).cast<String, dynamic>()));
  }

  Future<(String, User)> login(String username, String password) async {
    final j = await _req('POST', '/auth/login',
        body: {'username': username, 'password': password}, auth: false);
    return (j['token'] as String, User.fromJson((j['user'] as Map).cast<String, dynamic>()));
  }

  Future<User> me() async {
    final j = await _req('GET', '/auth/me');
    return User.fromJson((j['user'] as Map).cast<String, dynamic>());
  }

  Future<User> updateMe({String? displayName, String? avatar}) async {
    final j = await _req('PATCH', '/auth/me', body: {
      if (displayName != null) 'displayName': displayName,
      if (avatar != null) 'avatar': avatar,
    });
    return User.fromJson((j['user'] as Map).cast<String, dynamic>());
  }

  // ---------- users / friends ----------
  Future<List<User>> searchUsers(String q) async {
    final j = await _req('GET', '/users/search?q=${Uri.encodeQueryComponent(q)}');
    return (j['users'] as List)
        .map((e) => User.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<String> myQrPayload() async {
    final j = await _req('GET', '/users/qr');
    return j['payload'] as String;
  }

  Future<User> resolveUser(String uid) async {
    final j = await _req('GET', '/users/resolve/$uid');
    return User.fromJson((j['user'] as Map).cast<String, dynamic>());
  }

  Future<List<User>> friends() async {
    final j = await _req('GET', '/friends');
    return (j['friends'] as List)
        .map((e) => User.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<({List<FriendRequest> incoming, List<FriendRequest> outgoing})> friendRequests() async {
    final j = await _req('GET', '/friends/requests');
    List<FriendRequest> parse(dynamic l) => ((l ?? []) as List)
        .map((e) => FriendRequest.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (incoming: parse(j['incoming']), outgoing: parse(j['outgoing']));
  }

  Future<void> sendFriendRequest(String userId, {String? message}) async {
    await _req('POST', '/friends/request', body: {'userId': userId, if (message != null) 'message': message});
  }

  Future<void> respondFriendRequest(String requestId, bool accept) async {
    await _req('POST', '/friends/respond', body: {'requestId': requestId, 'accept': accept});
  }

  Future<void> deleteFriend(String userId) async {
    await _req('DELETE', '/friends/$userId');
  }

  Future<void> setFriendRemark(String userId, String remark) async {
    await _req('PATCH', '/friends/$userId', body: {'remark': remark});
  }

  Future<List<User>> blocks() async {
    final j = await _req('GET', '/blocks');
    return (j['blocks'] as List)
        .map((e) => User.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> blockUser(String userId) async {
    await _req('POST', '/blocks', body: {'userId': userId});
  }

  Future<void> unblockUser(String userId) async {
    await _req('DELETE', '/blocks/$userId');
  }

  // ---------- conversations ----------
  Future<List<Conversation>> conversations() async {
    final j = await _req('GET', '/conversations');
    return (j['conversations'] as List)
        .map((e) => Conversation.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Conversation> openPrivateConversation(String userId) async {
    final j = await _req('POST', '/conversations/private', body: {'userId': userId});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> createGroup(String name, List<String> memberIds) async {
    final j = await _req('POST', '/conversations/group', body: {'name': name, 'memberIds': memberIds});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> addGroupMembers(String conversationId, List<String> memberIds) async {
    final j = await _req('POST', '/conversations/$conversationId/members', body: {'memberIds': memberIds});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> renameGroup(String conversationId, String name) async {
    final j = await _req('PATCH', '/conversations/$conversationId', body: {'name': name});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> setGroupAdmin(String conversationId, String userId,
      {bool remove = false}) async {
    final j = await _req('POST', '/conversations/$conversationId/admins',
        body: {'userId': userId, 'remove': remove});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> muteMember(String conversationId, String userId, int minutes) async {
    final j = await _req('POST', '/conversations/$conversationId/mute',
        body: {'userId': userId, 'minutes': minutes});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> kickMember(String conversationId, String userId) async {
    final j = await _req('POST', '/conversations/$conversationId/kick',
        body: {'userId': userId});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<Conversation> transferOwner(String conversationId, String userId) async {
    final j = await _req('POST', '/conversations/$conversationId/transfer',
        body: {'userId': userId});
    return Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
  }

  Future<(Conversation, List<GroupMember>)> groupMembers(String conversationId) async {
    final j = await _req('GET', '/conversations/$conversationId/members');
    final conv = Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>());
    final members = (j['members'] as List)
        .map((e) => GroupMember.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (conv, members);
  }

  Future<List<Message>> messages(String conversationId, {int limit = 100}) async {
    final j = await _req('GET', '/conversations/$conversationId/messages?limit=$limit');
    return (j['messages'] as List)
        .map((e) => Message.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Message> sendMessage(String conversationId, {String? text, String? content, String type = 'text'}) async {
    final j = await _req('POST', '/conversations/$conversationId/messages',
        body: {'content': content ?? text ?? '', 'type': type});
    return Message.fromJson((j['message'] as Map).cast<String, dynamic>());
  }

  Future<void> recallMessage(String conversationId, String messageId) async {
    await _req('POST', '/conversations/$conversationId/messages/$messageId/recall');
  }

  Future<void> markRead(String conversationId) async {
    await _req('POST', '/conversations/$conversationId/read');
  }

  // ---------- moments ----------
  Future<List<Moment>> moments() async {
    final j = await _req('GET', '/moments');
    return (j['moments'] as List)
        .map((e) => Moment.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 服务器时间获取（/health 接口返回 time 字段）
  Future<int> serverTime() async {
    final j = await _req('GET', '/health', auth: false);
    return (j['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
  }

  Future<Moment> postMoment(String text, List<String> images) async {
    final j = await _req('POST', '/moments', body: {'text': text, 'images': images});
    return Moment.fromJson((j['moment'] as Map).cast<String, dynamic>());
  }

  Future<(bool, int)> likeMoment(String momentId) async {
    final j = await _req('POST', '/moments/$momentId/like');
    return (j['liked'] as bool? ?? false, (j['likeCount'] as num?)?.toInt() ?? 0);
  }

  Future<MomentComment> commentMoment(String momentId, String text) async {
    final j = await _req('POST', '/moments/$momentId/comment', body: {'text': text});
    return MomentComment.fromJson((j['comment'] as Map).cast<String, dynamic>());
  }

  /// 删除自己的炫圈（发布 2 分钟内）。
  Future<void> deleteMoment(String momentId) async {
    await _req('DELETE', '/moments/$momentId');
  }

  // ---------- upload ----------
  Future<String> uploadImage(Uint8List bytes, String ext) async {
    final j = await _req('POST', '/upload',
        body: {'data': base64Encode(bytes), 'ext': ext});
    return j['url'] as String;
  }

  /// 视频上传：application/octet-stream 原始二进制（避免 base64 额外开销）。
  Future<String> uploadVideo(Uint8List bytes, String ext) async {
    final uri = Uri.parse('$base/upload/video?ext=$ext');
    late http.Response res;
    try {
      res = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/octet-stream',
          'ngrok-skip-browser-warning': '1',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: bytes,
      );
    } catch (e) {
      throw ApiException(0, '网络连接失败，请检查服务器地址');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }
    if (res.statusCode >= 400) {
      throw ApiException(
          res.statusCode, json['message'] as String? ?? '视频上传失败 (${res.statusCode})');
    }
    return json['url'] as String;
  }
}
