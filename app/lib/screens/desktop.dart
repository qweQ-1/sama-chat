/// Windows / macOS / Linux 桌面版专属界面：
/// 左侧导航栏 + 三栏式消息区（会话列表 + 聊天窗），类微信/QQ 桌面版布局。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../updater.dart';
import '../widgets.dart';
import 'chat.dart';
import 'contacts.dart';
import 'moments.dart';
import 'new_group.dart';
import 'profile.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell>
    with WidgetsBindingObserver {
  int _tab = 0; // 0 消息 · 1 通讯录 · 2 炫圈 · 3 我
  String? _openConvId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<AppState>().handleResume();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().checkUpdateOnLaunch();
    });
  }

  /// 后台/定时检查发现的新版本，回到前台后弹窗。
  void _maybeShowPendingUpdate(AppState s) {
    final info = s.pendingUpdate;
    if (info == null || !s.appInForeground) return;
    s.pendingUpdate = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdateDialog(context, info);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = context.read<AppState>();
    if (state == AppLifecycleState.resumed) {
      s.handleResume();
      _maybeShowPendingUpdate(s);
    } else {
      s.handleBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    _maybeShowPendingUpdate(s);
    return Scaffold(
      body: Row(
        children: [
          _DesktopRail(
            tab: _tab,
            onSelect: (t) => setState(() => _tab = t),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_tab) {
              0 => _buildChatsArea(),
              1 => const ContactsTab(),
              2 => const MomentsTab(),
              _ => const ProfileTab(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatsArea() {
    final s = context.watch<AppState>();
    Conversation? open;
    if (_openConvId != null) {
      for (final c in s.conversations) {
        if (c.id == _openConvId) {
          open = c;
          break;
        }
      }
    }
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: _ChatListPane(
            selectedId: _openConvId,
            onSelect: (c) => setState(() => _openConvId = c.id),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: open == null
              ? const _ChatPlaceholder()
              : ChatScreen(
                  key: ValueKey('desktop-chat-${open.id}'),
                  conversation: open,
                ),
        ),
      ],
    );
  }
}

/// 左侧导航栏（头像 + 消息 / 通讯录 / 炫圈 / 我）。
class _DesktopRail extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onSelect;
  const _DesktopRail({required this.tab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 76,
      color: dark ? const Color(0xFF17171F) : const Color(0xFFF0F0F6),
      child: Column(
        children: [
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => onSelect(3),
            child: Tooltip(
              message: '我的',
              child: Avatar(
                  name: s.me?.displayName ?? '?', url: s.me?.avatar, size: 44),
            ),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: s.rtConnected ? '实时连接正常' : '实时连接断开（点击「我」查看诊断）',
            child: Icon(
              s.rtConnected ? Icons.bolt : Icons.bolt_outlined,
              size: 14,
              color: s.rtConnected ? const Color(0xFF22C55E) : Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          _RailItem(
              icon: Icons.chat_bubble_outline,
              label: '消息',
              selected: tab == 0,
              onTap: () => onSelect(0)),
          _RailItem(
              icon: Icons.people_outline,
              label: '通讯录',
              selected: tab == 1,
              onTap: () => onSelect(1)),
          _RailItem(
              icon: Icons.public,
              label: '炫圈',
              selected: tab == 2,
              onTap: () => onSelect(2)),
          const Spacer(),
          _RailItem(
              icon: Icons.person_outline,
              label: '我',
              selected: tab == 3,
              onTap: () => onSelect(3)),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 62,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.13) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10.5, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 会话列表栏。
class _ChatListPane extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<Conversation> onSelect;
  const _ChatListPane({required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text('消息',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
        ),
        const Divider(height: 1),
        Expanded(
          child: s.conversations.isEmpty
              ? const EmptyHint(
                  text: '还没有会话\n去通讯录找朋友聊天吧',
                  icon: Icons.forum_outlined)
              : ListView.builder(
                  itemCount: s.conversations.length,
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
                    return _DesktopConvTile(
                      conversation: c,
                      myId: me?.id,
                      avatarUrl: avatarUrl,
                      selected: c.id == selectedId,
                      onTap: () => onSelect(c),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DesktopConvTile extends StatelessWidget {
  final Conversation conversation;
  final String? myId;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback onTap;
  const _DesktopConvTile({
    required this.conversation,
    this.myId,
    this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final scheme = Theme.of(context).colorScheme;
    final time = formatShortTime(c.lastMessage?.createdAt ?? 0);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? scheme.primary.withValues(alpha: 0.09) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Stack(
              children: [
                Avatar(
                    name: c.name, url: c.isGroup ? null : avatarUrl, size: 44),
                if (c.isGroup)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child:
                          const Icon(Icons.group, size: 9, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.isGroup ? '${c.name} (${c.memberCount})' : c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5),
                        ),
                      ),
                      Text(time,
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 11.5)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          previewOf(c.lastMessage, myId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12.5),
                        ),
                      ),
                      if (c.unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            c.unread > 99 ? '99+' : '${c.unread}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10.5),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPlaceholder extends StatelessWidget {
  const _ChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 64, color: dark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 14),
          Text('选择一个会话开始聊天',
              style: TextStyle(
                  color: dark ? Colors.white38 : Colors.black38, fontSize: 14)),
        ],
      ),
    );
  }
}
