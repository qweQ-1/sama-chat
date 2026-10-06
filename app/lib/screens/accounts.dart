/// 切换账号：管理已保存的账号列表，点一下即可切换（无需重新输密码）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../store.dart';
import '../widgets.dart';
import 'login.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _busy = false;

  Future<void> _switch(SavedAccount acc) async {
    final s = context.read<AppState>();
    if (s.me?.id == acc.id || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await s.switchAccount(acc.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('已切换到 ${acc.displayName}'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) {
        showError(
            context,
            e.status == 401
                ? '该账号登录已过期，请用「添加账号」重新登录一次'
                : '切换失败：${e.message}');
      }
    } catch (e) {
      if (mounted) showError(context, '切换失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(SavedAccount acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('从列表中删除「${acc.displayName}」？\n以后需要重新输入密码登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await s.removeAccount(acc.id);
      if (!mounted) return;
      if (s.me == null) Navigator.of(context).pop(); // 已退出登录
    } catch (e) {
      if (mounted) showError(context, '删除失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen(addMode: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final accounts = s.savedAccounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('切换账号'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text('点一下即可切换，无需重新输密码',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('还没有保存的账号，点下面「添加账号」登录一个吧',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ),
          for (final acc in accounts)
            _AccountRow(
              acc: acc,
              current: s.me?.id == acc.id,
              busy: _busy,
              onTap: () => _switch(acc),
              onRemove: () => _remove(acc),
            ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: Icon(Icons.add_circle_outline, color: scheme.primary),
            title: const Text('添加账号',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('登录或注册另一个账号', style: TextStyle(fontSize: 12)),
            onTap: _busy ? null : _add,
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final nav = Navigator.of(context);
                      await context.read<AppState>().logout();
                      if (mounted) nav.pop();
                    },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('退出当前账号'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final SavedAccount acc;
  final bool current;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _AccountRow({
    required this.acc,
    required this.current,
    required this.busy,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: current ? scheme.primary : Colors.grey.shade300,
          width: current ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: busy ? null : onTap,
        leading: Avatar(name: acc.displayName, url: acc.avatar, size: 42),
        title: Row(children: [
          Flexible(
            child: Text(acc.displayName,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          if (current)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('当前',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
        ]),
        subtitle: Text(acc.ident,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        trailing: current
            ? Icon(Icons.check_circle, color: scheme.primary)
            : IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: Colors.grey.shade500),
                tooltip: '删除',
                onPressed: busy ? null : onRemove,
              ),
      ),
    );
  }
}
