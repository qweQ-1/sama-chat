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
  /// 注册：[username] 为空 = 快捷注册（按服务器模式自动生成用户名）。
  /// [code] 为验证码（邮箱模式=邮箱验证码，手机号模式=短信验证码）。
  Future<(String, User)> register({
    String? username,
    required String password,
    String? displayName,
    String? phone,
    String? email,
    String? code,
  }) async {
    final j = await _req('POST', '/auth/register', body: {
      if (username != null && username.trim().isNotEmpty)
        'username': username.trim(),
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (code != null) 'code': code,
    }, auth: false);
    return (j['token'] as String, User.fromJson((j['user'] as Map).cast<String, dynamic>()));
  }

  /// 登录第一步：查手机号/邮箱名下的所有账号。
  Future<List<User>> accounts({String? phone, String? email}) async {
    final j = await _req('POST', '/auth/accounts',
        body: {if (phone != null) 'phone': phone, if (email != null) 'email': email},
        auth: false);
    return (j['accounts'] as List)
        .map((e) => User.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 发送短信验证码。
  /// 返回 mode: 'sent'（已发送）| 'dev'（开发模式，验证码直接返回）| 'console'（管理员模式，码在服务器窗口）。
  Future<({String mode, String? devCode})> sendSmsCode(String phone) async {
    final j = await _req('POST', '/auth/sms/send', body: {'phone': phone}, auth: false);
    final mode = j['consoleMode'] == true
        ? 'console'
        : (j['devMode'] == true ? 'dev' : 'sent');
    return (mode: mode, devCode: j['devCode'] as String?);
  }

  /// 发送邮箱验证码（返回结构与短信相同）。
  Future<({String mode, String? devCode})> sendEmailCode(String email) async {
    final j = await _req('POST', '/auth/email/send', body: {'email': email}, auth: false);
    final mode = j['consoleMode'] == true
        ? 'console'
        : (j['devMode'] == true ? 'dev' : 'sent');
    return (mode: mode, devCode: j['devCode'] as String?);
  }

  /// 服务器当前的注册/登录模式：'email' | 'phone'。
  Future<String> fetchAuthMode() async {
    final j = await _req('GET', '/health', auth: false);
    return j['authMode'] as String? ?? 'email';
  }

  // ---------------- 公告 ----------------
  /// 拉取未读公告（登录后调用；弹过后要调 ackAnnouncements 标记已读）。
  Future<List<Announcement>> unreadAnnouncements() async {
    final j = await _req('GET', '/announce');
    return ((j['announcements'] as List?) ?? const [])
        .map((e) => Announcement.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 发布公告（仅 huzhi 等管理员账号，服务端强校验权限）。
  Future<void> publishAnnouncement(String content) async {
    await _req('POST', '/announce', body: {'content': content});
  }

  /// 标记公告已读（保证同一条公告「只弹一次」）。
  Future<void> ackAnnouncements(List<String> ids) async {
    await _req('POST', '/announce/ack', body: {'ids': ids});
  }

  // ---------------- 表情商店 ----------------
  /// 商店列表（最新在前）。
  Future<List<StickerPack>> stickerStore() async {
    final j = await _req('GET', '/stickers/store');
    return ((j['packs'] as List?) ?? const [])
        .map((e) => StickerPack.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 发布表情包（名称 + 已上传的图片 URL 列表）。
  Future<StickerPack> publishStickerPack(String name, List<String> urls) async {
    final j = await _req('POST', '/stickers/packs',
        body: {'name': name, 'stickers': urls});
    return StickerPack.fromJson((j['pack'] as Map).cast<String, dynamic>());
  }

  /// 下载表情包 → 之后可在聊天表情面板的「表情包」分区直接使用。
  Future<StickerPack> downloadStickerPack(String id) async {
    final j = await _req('POST', '/stickers/packs/$id/download');
    return StickerPack.fromJson((j['pack'] as Map).cast<String, dynamic>());
  }

  /// 我下载过的表情包。
  Future<List<StickerPack>> downloadedPacks() async {
    final j = await _req('GET', '/stickers/downloaded');
    return ((j['packs'] as List?) ?? const [])
        .map((e) => StickerPack.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 删除表情包（作者本人或管理员）。
  Future<void> deleteStickerPack(String id) async {
    await _req('DELETE', '/stickers/packs/$id');
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

  Future<User> updateMe({String? displayName, String? avatar, String? phone, String? email, String? code}) async {
    final j = await _req('PATCH', '/auth/me', body: {
      if (displayName != null) 'displayName': displayName,
      if (avatar != null) 'avatar': avatar,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (code != null) 'code': code,
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

  /// 退出群聊（群主需先转让或解散）。
  Future<void> leaveGroup(String conversationId) async {
    await _req('POST', '/conversations/$conversationId/leave');
  }

  /// 解散群聊（仅群主）。
  Future<void> disbandGroup(String conversationId) async {
    await _req('POST', '/conversations/$conversationId/disband');
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

  Future<Message> sendMessage(
    String conversationId, {
    String? text,
    String? content,
    String type = 'text',
    int? duration,
    String? fileName,
    int? fileSize,
    String? replyToId,
  }) async {
    final j = await _req('POST', '/conversations/$conversationId/messages', body: {
      'content': content ?? text ?? '',
      'type': type,
      if (duration != null) 'duration': duration,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (replyToId != null && replyToId.isNotEmpty) 'replyToId': replyToId,
    });
    return Message.fromJson((j['message'] as Map).cast<String, dynamic>());
  }

  Future<void> recallMessage(String conversationId, String messageId) async {
    await _req('POST', '/conversations/$conversationId/messages/$messageId/recall');
  }

  // ---------- 搜索 ----------
  Future<List<SearchHit>> search(String q) async {
    final j = await _req('GET', '/search?q=${Uri.encodeQueryComponent(q)}');
    return ((j['results'] as List?) ?? const [])
        .map((e) => SearchHit.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ---------- 会话偏好（置顶 / 免打扰）----------
  Future<({bool pinned, bool muted})> setConvPrefs(
    String conversationId, {
    bool? pinned,
    bool? muted,
  }) async {
    final j = await _req('POST', '/conversations/$conversationId/prefs', body: {
      if (pinned != null) 'pinned': pinned,
      if (muted != null) 'muted': muted,
    });
    return (
      pinned: j['pinned'] as bool? ?? false,
      muted: j['muted'] as bool? ?? false,
    );
  }

  // ---------- 文件上传（任意类型）----------
  Future<({String url, String name, int size})> uploadFile(
    Uint8List bytes,
    String fileName,
  ) async {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        : '';
    final uri = Uri.parse(
        '$base/upload/file?ext=$ext&name=${Uri.encodeQueryComponent(fileName)}');
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
      ).timeout(const Duration(seconds: 300));
    } catch (e) {
      throw ApiException(0, '文件上传失败，请检查网络');
    }
    if (res.statusCode != 200) {
      Map<String, dynamic> j0 = {};
      try {
        j0 = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      throw ApiException(
          res.statusCode, j0['message'] as String? ?? '文件上传失败 (${res.statusCode})');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (
      url: j['url'] as String,
      name: j['name'] as String? ?? fileName,
      size: (j['size'] as num?)?.toInt() ?? bytes.length,
    );
  }

  Future<void> markRead(String conversationId) async {
    await _req('POST', '/conversations/$conversationId/read');
  }

  // ---------- 群投票 ----------
  Future<Poll> createPoll(String conversationId, String question, List<String> options) async {
    final j = await _req('POST', '/conversations/$conversationId/polls',
        body: {'question': question, 'options': options});
    return Poll.fromJson((j['poll'] as Map).cast<String, dynamic>());
  }

  Future<List<Poll>> polls(String conversationId) async {
    final j = await _req('GET', '/conversations/$conversationId/polls');
    return ((j['polls'] as List?) ?? const [])
        .map((e) => Poll.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Poll> votePoll(String pollId, List<String> optionIds) async {
    final j = await _req('POST', '/polls/$pollId/vote', body: {'optionIds': optionIds});
    return Poll.fromJson((j['poll'] as Map).cast<String, dynamic>());
  }

  Future<Poll> closePoll(String pollId) async {
    final j = await _req('POST', '/polls/$pollId/close');
    return Poll.fromJson((j['poll'] as Map).cast<String, dynamic>());
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
