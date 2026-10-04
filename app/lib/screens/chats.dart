import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat.dart';
import 'new_group.dart';

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
      title: Text(
        c.isGroup ? '${c.name} (${c.memberCount})' : c.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
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
          if (c.unread > 0)
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
          else
            const SizedBox(height: 16),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
      ),
    );
  }
}
