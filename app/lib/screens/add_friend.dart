import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// Search users by username / nickname and send friend requests.
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<User> _results = [];
  bool _searching = false;
  final Set<String> _sent = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await context.read<AppState>().api.searchUsers(q.trim());
      if (mounted) setState(() => _results = r);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(User u) async {
    final s = context.read<AppState>();
    try {
      await s.api.sendFriendRequest(u.id);
      setState(() => _sent.add(u.id));
      await s.refreshRequests();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<AppState>().friends;
    return Scaffold(
      appBar: AppBar(title: const Text('添加朋友')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              onChanged: _onChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '输入用户名 / 昵称搜索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? const EmptyHint(
                    text: '搜索到用户后可发送好友请求', icon: Icons.person_search)
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final u = _results[i];
                      final isFriend = friends.any((f) => f.id == u.id);
                      final sent = _sent.contains(u.id);
                      return ListTile(
                        leading: Avatar(name: u.displayName, url: u.avatar, size: 44),
                        title: Text(u.displayName),
                        subtitle: Text('@${u.username}',
                            style: const TextStyle(fontSize: 12)),
                        trailing: isFriend
                            ? const Text('已是好友',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 13))
                            : sent
                                ? const Text('已发送',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 13))
                                : FilledButton(
                                    onPressed: () => _add(u),
                                    child: const Text('添加'),
                                  ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Incoming friend requests: accept / reject.
class FriendRequestsScreen extends StatelessWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final reqs = s.incomingRequests;

    return Scaffold(
      appBar: AppBar(title: const Text('新的朋友')),
      body: RefreshIndicator(
        onRefresh: () => s.refreshRequests(),
        child: reqs.isEmpty
            ? ListView(children: const [
                SizedBox(height: 180),
                EmptyHint(text: '暂无新的好友请求', icon: Icons.person_add_alt),
              ])
            : ListView.builder(
                itemCount: reqs.length,
                itemBuilder: (context, i) {
                  final r = reqs[i];
                  final from = r.from;
                  return ListTile(
                    leading: Avatar(
                        name: from?.displayName ?? '?', url: from?.avatar, size: 46),
                    title: Text(from?.displayName ?? '未知用户'),
                    subtitle: Text('@${from?.username ?? ''} 请求加你为好友',
                        style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () async {
                            try {
                              await s.api.respondFriendRequest(r.id, false);
                              await s.refreshRequests();
                            } on ApiException catch (e) {
                              showError(context, e.message);
                            }
                          },
                          child: const Text('拒绝'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            try {
                              await s.api.respondFriendRequest(r.id, true);
                              await s.refreshFriends();
                              await s.refreshRequests();
                            } on ApiException catch (e) {
                              showError(context, e.message);
                            }
                          },
                          child: const Text('接受'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
