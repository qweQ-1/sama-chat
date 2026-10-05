import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// 群聊信息 / 群管理：改群名、管理员、禁言、踢人、转让群主。
class GroupInfoScreen extends StatefulWidget {
  final Conversation conversation;
  const GroupInfoScreen({super.key, required this.conversation});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Conversation? _conv;
  List<GroupMember> _members = [];
  bool _loading = true;

  String? get _myId => context.read<AppState>().me?.id;

  bool get _canManage {
    final c = _conv;
    final me = _myId;
    if (c == null || me == null) return false;
    return c.ownerId == me || c.adminIds.contains(me);
  }

  bool get _amOwner {
    final c = _conv;
    final me = _myId;
    return c != null && me != null && c.ownerId == me;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final (conv, members) = await s.api.groupMembers(widget.conversation.id);
      if (mounted) {
        setState(() {
          _conv = conv;
          _members = members;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.message);
      }
    }
  }

  Future<void> _runOp(Future<void> Function() op, {String? done}) async {
    try {
      await op();
      await _load();
      if (mounted) await context.read<AppState>().refreshConversations();
      if (done != null && mounted) showError(context, done);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  Future<void> _rename() async {
    final s = context.read<AppState>();
    final controller = TextEditingController(text: _conv?.name ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改群名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
    if (value == null || value.isEmpty) return;
    await _runOp(() => s.api.renameGroup(widget.conversation.id, value),
        done: '群名称已更新 ✓');
  }

  void _memberSheet(GroupMember m) {
    final me = _myId;
    final c = _conv;
    if (c == null || me == null) return;
    if (m.user.id == me || !_canManage) return;
    // 管理员只能操作普通成员；群主可操作除自己外所有人
    final canActOnTarget = c.ownerId == me ||
        (c.adminIds.contains(me) && !m.isAdmin && !m.isOwner);
    if (!canActOnTarget) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_amOwner && !m.isOwner) ...[
              ListTile(
                leading: Icon(m.isAdmin
                    ? Icons.remove_moderator_outlined
                    : Icons.military_tech_outlined),
                title: Text(m.isAdmin ? '取消管理员' : '设为管理员'),
                onTap: () {
                  Navigator.pop(ctx);
                  _runOp(
                    () => context.read<AppState>().api.setGroupAdmin(
                        widget.conversation.id, m.user.id,
                        remove: m.isAdmin),
                    done: m.isAdmin ? '已取消管理员' : '已设为管理员 ✓',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('转让群主'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmTransfer(m);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: Text(m.muted ? '禁言设置（当前：禁言中）' : '禁言'),
              onTap: () {
                Navigator.pop(ctx);
                _muteSheet(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('踢出群聊'),
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                _confirmKick(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _muteSheet(GroupMember m) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.muted)
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('解除禁言'),
                onTap: () {
                  Navigator.pop(ctx);
                  _runOp(
                    () => context.read<AppState>().api.muteMember(
                        widget.conversation.id, m.user.id, 0),
                    done: '已解除禁言 ✓',
                  );
                },
              ),
            for (final opt in const [
              ('禁言 10 分钟', 10),
              ('禁言 1 小时', 60),
              ('禁言 1 天', 1440),
            ])
              ListTile(
                title: Text(opt.$1),
                onTap: () {
                  Navigator.pop(ctx);
                  _runOp(
                    () => context.read<AppState>().api.muteMember(
                        widget.conversation.id, m.user.id, opt.$2),
                    done: '${m.user.shownName} ${opt.$1} ✓',
                  );
                },
              ),
            ListTile(
              title: const Text('永久禁言'),
              textColor: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                _runOp(
                  () => context.read<AppState>().api.muteMember(
                      widget.conversation.id, m.user.id, -1),
                  done: '已永久禁言 ✓',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmKick(GroupMember m) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('踢出群聊'),
        content: Text('确定把「${m.user.shownName}」踢出群聊吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('踢出'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runOp(() => s.api.kickMember(widget.conversation.id, m.user.id),
        done: '已踢出群聊');
  }

  Future<void> _confirmTransfer(GroupMember m) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('转让群主'),
        content: Text('将群主转让给「${m.user.shownName}」？\n\n'
            '· 转让后你将成为管理员\n'
            '· 群主转让每 30 天只能进行一次'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认转让'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runOp(() => s.api.transferOwner(widget.conversation.id, m.user.id),
        done: '已转让群主 ✓');
  }

  Widget _badge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _conv ?? widget.conversation;
    return Scaffold(
      appBar: AppBar(title: const Text('群聊信息')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 6),
                ListTile(
                  title: const Text('群名称'),
                  subtitle: Text(c.name),
                  trailing: _canManage
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _rename,
                        )
                      : null,
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('群成员',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ),
                ..._members.map((m) => ListTile(
                      leading: Avatar(
                          name: m.user.displayName,
                          url: m.user.avatar,
                          size: 44),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              m.user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (m.isOwner) _badge('群主', const Color(0xFFF59E0B)),
                          if (m.isAdmin) _badge('管理员', const Color(0xFF3B82F6)),
                          if (m.muted) _badge('禁言中', Colors.grey),
                        ],
                      ),
                      trailing: (m.user.id != _myId && _canManage)
                          ? IconButton(
                              icon: const Icon(Icons.more_horiz),
                              onPressed: () => _memberSheet(m),
                            )
                          : null,
                    )),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
