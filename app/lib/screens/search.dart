/// 搜索：查找聊天记录（全部会话中搜文字消息）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  List<SearchHit> _hits = const [];
  bool _busy = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await context.read<AppState>().api.search(q);
      if (mounted) {
        setState(() {
          _hits = hits;
          _searched = true;
          _busy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.status == 404
              ? '需要服务器更新到 v2.2.0 才支持搜索'
              : e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  void _openHit(SearchHit hit) {
    final s = context.read<AppState>();
    final conv = s.conversations.where((c) => c.id == hit.conversationId).toList();
    if (conv.isEmpty) {
      showError(context, '会话不存在（可能已退群或被解散）');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv.first)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索聊天记录')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: '输入要搜索的文字…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _busy ? null : _run,
                ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!,
                  style: TextStyle(color: Colors.orange.shade700, fontSize: 13)),
            ),
          if (_searched && !_busy && _hits.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('没有找到相关聊天记录',
                  style: TextStyle(color: Colors.grey.shade500)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _hits.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) {
                final h = _hits[i];
                return ListTile(
                  leading: Icon(h.isGroup ? Icons.groups_outlined : Icons.person_outline),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(h.conversationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                      const SizedBox(width: 8),
                      Text(formatTime(h.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                  subtitle: Text.rich(
                    TextSpan(
                      children: [
                        if (h.senderName.isNotEmpty)
                          TextSpan(
                            text: '${h.senderName}: ',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        TextSpan(text: h.content),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => _openHit(h),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
