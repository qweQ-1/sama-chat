import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'add_friend.dart';
import 'chat.dart';
import 'qr.dart';

class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  Future<void> _openChat(BuildContext context, User user) async {
    final s = context.read<AppState>();
    try {
      final conv = await s.openPrivateChat(user);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)),
      );
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  void _friendSheet(BuildContext context, User f) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('发消息'),
              onTap: () {
                Navigator.pop(ctx);
                _openChat(context, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('设置备注'),
              onTap: () {
                Navigator.pop(ctx);
                _editRemark(context, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('删除好友'),
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                _deleteFriend(context, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('加入黑名单'),
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                _blockFriend(context, f);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRemark(BuildContext context, User f) async {
    final s = context.read<AppState>();
    final controller = TextEditingController(text: f.remark);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设置备注（${f.displayName}）'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            hintText: '留空则恢复显示原昵称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await s.api.setFriendRemark(f.id, value);
      await s.refreshFriends();
      await s.refreshConversations();
      if (context.mounted) showError(context, '备注已更新 ✓');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  Future<void> _deleteFriend(BuildContext context, User f) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除「${f.shownName}」吗？\n（双方好友列表都会移除）'),
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
    try {
      await s.api.deleteFriend(f.id);
      await s.refreshFriends();
      await s.refreshConversations();
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  Future<void> _blockFriend(BuildContext context, User f) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入黑名单'),
        content: Text(
            '将「${f.shownName}」加入黑名单？\n对方将无法给你发消息，互相看不到炫圈动态。\n（好友关系保留，解除黑名单后立即恢复正常）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('拉黑'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.api.blockUser(f.id);
      await s.refreshFriends();
      await s.refreshConversations();
      if (context.mounted) showError(context, '已加入黑名单');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pending = s.incomingRequests.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: '添加朋友',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddFriendScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => s.refreshFriends(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFF59E0B),
                child: const Icon(Icons.person_add_alt_1, color: Colors.white),
              ),
              title: const Text('新的朋友'),
              trailing: pending > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$pending',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF10B981),
                child: Icon(Icons.qr_code_2, color: Colors.white),
              ),
              title: const Text('我的二维码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyQrScreen()),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF3B82F6),
                child: Icon(Icons.qr_code_scanner, color: Colors.white),
              ),
              title: const Text('扫一扫（面对面加好友）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text('我的好友',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            if (s.friends.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyHint(
                    text: '还没有好友，点右上角添加或扫码面对面加人',
                    icon: Icons.group_outlined),
              )
            else
              ...s.friends.map((f) {
                final online = s.onlineUserIds.contains(f.id);
                return ListTile(
                  leading: Stack(
                    children: [
                      Avatar(name: f.displayName, url: f.avatar, size: 46),
                      if (online)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(f.shownName),
                  subtitle: Text(
                      f.remark.isNotEmpty
                          ? '${f.displayName} · @${f.username}'
                          : '@${f.username}',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () => _friendSheet(context, f),
                  ),
                  onTap: () => _openChat(context, f),
                );
              }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
