/// 发布公告（仅 huzhi 等管理员账号可见的入口）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../store.dart';
import '../widgets.dart';

class PublishAnnouncementScreen extends StatefulWidget {
  const PublishAnnouncementScreen({super.key});

  @override
  State<PublishAnnouncementScreen> createState() =>
      _PublishAnnouncementScreenState();
}

class _PublishAnnouncementScreenState extends State<PublishAnnouncementScreen> {
  final _content = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _content.text.trim();
    if (text.isEmpty) {
      showError(context, '请先输入公告内容');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await context.read<AppState>().publishAnnouncement(text);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('公告已发布 ✓ 所有人下次打开 App 时会看到（每人只弹一次）'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (mounted) showError(context, '发布失败：${e.message}');
    } catch (e) {
      if (mounted) showError(context, '发布失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布公告')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '发布后，所有用户会在打开软件并登录后收到这条公告（每人只弹一次，不会重复打扰）。',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              maxLines: 8,
              minLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: '输入公告内容…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('发布给所有人'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
