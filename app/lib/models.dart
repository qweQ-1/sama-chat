/// Data models mirroring the sama-chat server API.
library;

class User {
  final String id;
  final String username;
  final String displayName;
  final String? avatar;
  final String remark; // 好友备注（仅好友列表返回）
  final String phone; // 绑定的手机号（仅自己的账号信息里返回）
  final String email; // 绑定的邮箱（仅自己的账号信息里返回）

  User({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatar,
    this.remark = '',
    this.phone = '',
    this.email = '',
  });

  /// 显示名：有备注优先用备注
  String get shownName => remark.isNotEmpty ? remark : displayName;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String? ?? '',
        displayName: j['displayName'] as String? ?? j['username'] as String? ?? '',
        avatar: j['avatar'] as String?,
        remark: j['remark'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'avatar': avatar,
        'phone': phone,
        'email': email,
      };
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String type; // 'text' | 'image' | 'video'
  final String content;
  final int createdAt;
  final List<String> readBy;
  final User? sender;
  final bool recalled;
  final bool pending; // 本地乐观消息（还没被服务器确认）
  final bool failed;  // 发送失败

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.content,
    required this.createdAt,
    required this.readBy,
    this.sender,
    this.recalled = false,
    this.pending = false,
    this.failed = false,
  });

  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String,
        senderId: j['senderId'] as String,
        type: j['type'] as String? ?? 'text',
        content: j['content'] as String? ?? '',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        readBy:
            (j['readBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        sender: j['sender'] != null
            ? User.fromJson((j['sender'] as Map).cast<String, dynamic>())
            : null,
        recalled: j['recalled'] as bool? ?? false,
      );

  Message copyWith({String? content, bool? recalled, bool? pending, bool? failed}) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        content: content ?? this.content,
        createdAt: createdAt,
        readBy: readBy,
        sender: sender,
        recalled: recalled ?? this.recalled,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );
}

class Conversation {
  final String id;
  final String type; // 'private' | 'group'
  final String name;
  final List<String> memberIds;
  final int memberCount;
  final Message? lastMessage;
  final int unread;
  final String? ownerId;
  final List<String> adminIds;
  final Map<String, int> mutes;

  Conversation({
    required this.id,
    required this.type,
    required this.name,
    required this.memberIds,
    required this.memberCount,
    this.lastMessage,
    this.unread = 0,
    this.ownerId,
    this.adminIds = const [],
    this.mutes = const {},
  });

  bool get isGroup => type == 'group';

  bool canManage(String? myId) =>
      isGroup && myId != null && (ownerId == myId || adminIds.contains(myId));

  bool isOwner(String? myId) => isGroup && ownerId != null && ownerId == myId;

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'private',
        name: j['name'] as String? ?? '聊天',
        memberIds:
            (j['memberIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        lastMessage: j['lastMessage'] != null
            ? Message.fromJson((j['lastMessage'] as Map).cast<String, dynamic>())
            : null,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        ownerId: j['ownerId'] as String?,
        adminIds:
            (j['adminIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        mutes: (j['mutes'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {},
      );

  Conversation copyWith({Message? lastMessage, int? unread}) => Conversation(
        id: id,
        type: type,
        name: name,
        memberIds: memberIds,
        memberCount: memberCount,
        lastMessage: lastMessage ?? this.lastMessage,
        unread: unread ?? this.unread,
        ownerId: ownerId,
        adminIds: adminIds,
        mutes: mutes,
      );
}

/// 群成员（含角色与禁言状态）
class GroupMember {
  final User user;
  final String role; // owner | admin | member
  final int mutedUntil; // 0=未禁言, -1=永久, >0=时间戳

  GroupMember({required this.user, required this.role, required this.mutedUntil});

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';

  bool get muted {
    if (mutedUntil == 0) return false;
    if (mutedUntil < 0) return true;
    return serverNowMs() < mutedUntil;
  }

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        user: User.fromJson(j),
        role: j['role'] as String? ?? 'member',
        mutedUntil: (j['mutedUntil'] as num?)?.toInt() ?? 0,
      );
}

class FriendRequest {
  final String id;
  final String fromId;
  final String toId;
  final String status;
  final int createdAt;
  final User? from;
  final User? to;

  FriendRequest({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.status,
    required this.createdAt,
    this.from,
    this.to,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
        id: j['id'] as String,
        fromId: j['fromId'] as String,
        toId: j['toId'] as String,
        status: j['status'] as String? ?? 'pending',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        from: j['from'] != null
            ? User.fromJson((j['from'] as Map).cast<String, dynamic>())
            : null,
        to: j['to'] != null
            ? User.fromJson((j['to'] as Map).cast<String, dynamic>())
            : null,
      );
}

class MomentComment {
  final String id;
  final User? author;
  final String text;
  final int createdAt;

  MomentComment({
    required this.id,
    this.author,
    required this.text,
    required this.createdAt,
  });

  factory MomentComment.fromJson(Map<String, dynamic> j) => MomentComment(
        id: j['id'] as String,
        author: j['author'] != null
            ? User.fromJson((j['author'] as Map).cast<String, dynamic>())
            : null,
        text: j['text'] as String? ?? '',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

class Moment {
  final String id;
  final User? author;
  final String text;
  final List<String> images;
  final int createdAt;
  final int likeCount;
  final bool likedByMe;
  final List<MomentComment> comments;

  Moment({
    required this.id,
    this.author,
    required this.text,
    required this.images,
    required this.createdAt,
    required this.likeCount,
    required this.likedByMe,
    required this.comments,
  });

  factory Moment.fromJson(Map<String, dynamic> j) => Moment(
        id: j['id'] as String,
        author: j['author'] != null
            ? User.fromJson((j['author'] as Map).cast<String, dynamic>())
            : null,
        text: j['text'] as String? ?? '',
        images:
            (j['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        likeCount: (j['likeCount'] as num?)?.toInt() ??
            ((j['likes'] as List?)?.length ?? 0),
        likedByMe: j['likedByMe'] as bool? ?? false,
        comments: (j['comments'] as List?)
                ?.map((e) => MomentComment.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
      );

  Moment copyWith({int? likeCount, bool? likedByMe, List<MomentComment>? comments}) =>
      Moment(
        id: id,
        author: author,
        text: text,
        images: images,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        comments: comments ?? this.comments,
      );
}

/// 服务器时间偏移（毫秒）：手机时钟不准时，用 serverNowMs() 代替 DateTime.now()。
int serverTimeOffsetMs = 0;

int serverNowMs() => DateTime.now().millisecondsSinceEpoch + serverTimeOffsetMs;

/// Parse `samachat://add?uid=u_xxx` QR payloads (or a bare user id).
String? parseAddPayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final uri = Uri.parse(raw);
    final uid = uri.queryParameters['uid'];
    if (uid != null && uid.isNotEmpty) return uid;
  } catch (_) {}
  if (raw.startsWith('u_') && raw.length > 3) return raw;
  return null;
}

/// Human-friendly relative time for chat / moments.
String formatTime(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.fromMillisecondsSinceEpoch(serverNowMs());
  final diff = now.difference(dt);

  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hm =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (sameDay) return hm;
  final yesterday = now.subtract(const Duration(days: 1));
  if (dt.year == yesterday.year &&
      dt.month == yesterday.month &&
      dt.day == yesterday.day) {
    return '昨天 $hm';
  }
  if (dt.year == now.year) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hm';
  }
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// Short label for conversation list.
String formatShortTime(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (dt.year == yesterday.year &&
      dt.month == yesterday.month &&
      dt.day == yesterday.day) {
    return '昨天';
  }
  return '${dt.month}/${dt.day}';
}
