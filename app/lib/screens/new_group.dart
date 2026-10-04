import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selected.isEmpty) {
      showError(context, '至少选择一位好友');
      return;
    }
    setState(() => _busy = true);
    final s = context.read<AppState>();
    try {
      final conv = await s.createGroup(
        _name.text.trim().isEmpty ? '新群聊' : _name.text.trim(),
        _selected.toList(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)),
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<AppState>().friends;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发起群聊'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('创建 (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: '群名称',
                hintText: '给群聊起个名字',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('选择成员',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: friends.isEmpty
                ? const EmptyHint(
                    text: '还没有好友，先去通讯录加好友吧', icon: Icons.group_outlined)
                : ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (context, i) {
                      final f = friends[i];
                      final checked = _selected.contains(f.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(f.id);
                          } else {
                            _selected.remove(f.id);
                          }
                        }),
                        secondary:
                            Avatar(name: f.displayName, url: f.avatar, size: 42),
                        title: Text(f.displayName),
                        subtitle: Text('@${f.username}',
                            style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
