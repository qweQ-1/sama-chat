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

  Api(this.base);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
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
          res = await http.get(uri, headers: _headers);
        case 'POST':
          res = await http.post(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
        case 'PATCH':
          res = await http.patch(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
        case 'DELETE':
          res = await http.delete(uri, headers: _headers);
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

  // ---------- upload ----------
  Future<String> uploadImage(Uint8List bytes, String ext) async {
    final j = await _req('POST', '/upload',
        body: {'data': base64Encode(bytes), 'ext': ext});
    return j['url'] as String;
  }
}
