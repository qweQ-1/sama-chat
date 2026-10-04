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
                  title: Text(f.displayName),
                  subtitle: Text('@${f.username}',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
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
