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
    if (c.ownerId == me || c.adminIds.contains(me)) return true;
    // 兜底：以服务器返回的成员角色为准
    return _members.any((m) => m.user.id == me && (m.isOwner || m.isAdmin));
  }

  /// 我能否对某个成员执行管理操作
  bool _canActOn(GroupMember m) {
    final c = _conv;
    final me = _myId;
    if (c == null || me == null) return false;
    if (m.user.id == me) return false;
    return c.ownerId == me ||
        (c.adminIds.contains(me) && !m.isAdmin && !m.isOwner);
  }

  String get _roleHint {
    final c = _conv;
    final me = _myId;
    if (c == null || me == null) return '';
    final mine = _members.where((m) => m.user.id == me).toList();
    final role = mine.isNotEmpty
        ? mine.first.role
        : (c.ownerId == me
            ? 'owner'
            : (c.adminIds.contains(me) ? 'admin' : 'member'));
    switch (role) {
      case 'owner':
        return '你是群主：可以修改群名称、设置管理员、禁言、踢人、转让群主\n（点击成员条目即可管理）';
      case 'admin':
        return '你是管理员：可以修改群名称、禁言、踢出普通成员\n（点击成员条目即可管理）';
      default:
        return '你是普通成员：群名称与成员管理由群主/管理员操作';
    }
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
    if (!_canActOn(m)) return;

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
                  onTap: _canManage ? _rename : null,
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
                      trailing: _canActOn(m)
                          ? IconButton(
                              icon: const Icon(Icons.more_horiz),
                              onPressed: () => _memberSheet(m),
                            )
                          : null,
                      onTap: _canActOn(m) ? () => _memberSheet(m) : null,
                    )),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    _roleHint,
                    style: const TextStyle(
                        fontSize: 12.5, color: Colors.grey, height: 1.6),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                // 退出 / 解散群聊
                if (!_amOwner)
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text('退出群聊',
                        style: TextStyle(color: Colors.redAccent)),
                    onTap: _loading ? null : _confirmLeave,
                  )
                else ...[
                  ListTile(
                    leading: const Icon(Icons.group_off_outlined,
                        color: Colors.redAccent),
                    title: const Text('解散群聊',
                        style: TextStyle(color: Colors.redAccent)),
                    subtitle: const Text('所有成员都会失去这个群（不可恢复）',
                        style: TextStyle(fontSize: 12)),
                    onTap: _loading ? null : _confirmDisband,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '群主不能直接退群：想让群继续存在，请先在成员里「转让群主」。',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  /// 退出群聊（普通成员）。
  Future<void> _confirmLeave() async {
    final c = _conv ?? widget.conversation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出群聊'),
        content: Text('确定退出「${c.name}」吗？\n退出后将不再收到该群消息。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.leaveGroup(c.id);
      // 关掉群信息页 + 聊天页，回到会话列表
      nav.pop(); // group info
      if (nav.canPop()) nav.pop(); // chat
      messenger.showSnackBar(SnackBar(
        content: Text('已退出「${c.name}」'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '退出失败：$e');
    }
  }

  /// 解散群聊（群主）。
  Future<void> _confirmDisband() async {
    final c = _conv ?? widget.conversation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散群聊'),
        content: Text(
            '确定解散「${c.name}」吗？\n\n所有成员都会立即失去这个群，聊天记录也会被清除，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.disbandGroup(c.id);
      nav.pop();
      if (nav.canPop()) nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('「${c.name}」已解散'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '解散失败：$e');
    }
  }
}
