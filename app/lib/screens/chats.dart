import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat.dart';
import 'new_group.dart';
import 'search.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: '搜索聊天记录',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: '发起群聊',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NewGroupScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => s.refreshConversations(),
        child: s.conversations.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 180),
                  EmptyHint(text: '还没有会话，去通讯录找朋友聊天吧', icon: Icons.forum_outlined),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: s.conversations.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 76),
                itemBuilder: (context, i) {
                  final c = s.conversations[i];
                  String? avatarUrl;
                  if (!c.isGroup && me != null) {
                    final otherId = c.memberIds.firstWhere(
                      (m) => m != me.id,
                      orElse: () => '',
                    );
                    for (final f in s.friends) {
                      if (f.id == otherId) {
                        avatarUrl = f.avatar;
                        break;
                      }
                    }
                  }
                  return _ConversationTile(
                      conversation: c, myId: me?.id, avatarUrl: avatarUrl);
                },
              ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String? myId;
  final String? avatarUrl;
  const _ConversationTile({required this.conversation, this.myId, this.avatarUrl});

  Future<void> _showActions(BuildContext context) async {
    final s = context.read<AppState>();
    final c = conversation;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(c.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin),
              title: Text(c.pinned ? '取消置顶' : '置顶聊天'),
              onTap: () {
                Navigator.pop(ctx);
                s.setConvPrefs(c.id, pinned: !c.pinned);
              },
            ),
            ListTile(
              leading: Icon(c.muted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined),
              title: Text(c.muted ? '取消免打扰' : '消息免打扰'),
              onTap: () {
                Navigator.pop(ctx);
                s.setConvPrefs(c.id, muted: !c.muted);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final time = formatShortTime(c.lastMessage?.createdAt ?? 0);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          Avatar(
            name: c.name,
            url: c.isGroup ? null : avatarUrl,
            size: 50,
          ),
          if (c.isGroup)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.group, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              c.isGroup ? '${c.name} (${c.memberCount})' : c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (c.muted)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.notifications_off_outlined,
                  size: 14, color: Colors.grey.shade400),
            ),
        ],
      ),
      subtitle: Text(
        previewOf(c.lastMessage, myId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          const SizedBox(height: 4),
          if (c.unread > 0 && !c.muted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                c.unread > 99 ? '99+' : '${c.unread}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            )
          else if (c.unread > 0)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            const SizedBox(height: 16),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
      ),
      onLongPress: () => _showActions(context),
    );
  }
}
