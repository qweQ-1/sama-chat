import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// 黑名单管理：查看 + 解除。
class BlockListScreen extends StatefulWidget {
  const BlockListScreen({super.key});

  @override
  State<BlockListScreen> createState() => _BlockListScreenState();
}

class _BlockListScreenState extends State<BlockListScreen> {
  List<User> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AppState>().api.blocks();
      if (mounted) {
        setState(() {
          _blocks = list;
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

  Future<void> _unblock(User u) async {
    final s = context.read<AppState>();
    try {
      await s.api.unblockUser(u.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('黑名单')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocks.isEmpty
              ? const EmptyHint(
                  text: '黑名单是空的 —— 拉黑的人会出现在这里',
                  icon: Icons.block)
              : ListView.builder(
                  itemCount: _blocks.length,
                  itemBuilder: (context, i) {
                    final u = _blocks[i];
                    return ListTile(
                      leading:
                          Avatar(name: u.displayName, url: u.avatar, size: 44),
                      title: Text(u.displayName),
                      subtitle: Text('@${u.username}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: OutlinedButton(
                        onPressed: () => _unblock(u),
                        child: const Text('解除'),
                      ),
                    );
                  },
                ),
    );
  }
}
