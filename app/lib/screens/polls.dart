/// 群投票页：查看 / 发起 / 参与投票。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class PollsScreen extends StatefulWidget {
  final Conversation conversation;
  const PollsScreen({super.key, required this.conversation});

  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await context.read<AppState>().loadPolls(widget.conversation.id);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() async {
    final questionCtl = TextEditingController();
    final optionCtls = <TextEditingController>[
      TextEditingController(),
      TextEditingController(),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('发起投票'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: questionCtl,
                    decoration: const InputDecoration(
                      labelText: '投票主题',
                      hintText: '今晚吃啥？',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < optionCtls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: optionCtls[i],
                        decoration: InputDecoration(
                          labelText: '选项 ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: optionCtls.length > 2
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 18),
                                  onPressed: () => setSt(() {
                                    optionCtls.removeAt(i).dispose();
                                  }),
                                )
                              : null,
                        ),
                      ),
                    ),
                  if (optionCtls.length < 10)
                    TextButton.icon(
                      onPressed: () => setSt(() {
                        optionCtls.add(TextEditingController());
                      }),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('加一个选项'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('发起')),
          ],
        ),
      ),
    );
    final question = questionCtl.text.trim();
    final options = optionCtls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    questionCtl.dispose();
    for (final c in optionCtls) {
      c.dispose();
    }
    if (ok != true || !mounted) return;
    if (question.isEmpty || options.length < 2) {
      showError(context, '主题和至少 2 个选项都要填哦');
      return;
    }
    try {
      await context.read<AppState>().api.createPoll(widget.conversation.id, question, options);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  Future<void> _vote(Poll p, PollOption o) async {
    if (_busy.contains(p.id)) return;
    setState(() => _busy.add(p.id));
    final s = context.read<AppState>();
    try {
      await s.api.votePoll(p.id, [o.id]);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _close(Poll p) async {
    try {
      await context.read<AppState>().api.closePoll(p.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.polls[widget.conversation.id] ?? const <Poll>[];
    final meId = s.me?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('群投票'),
        actions: [
          IconButton(
            tooltip: '发起投票',
            icon: const Icon(Icons.add),
            onPressed: _create,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: list.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 160),
                      EmptyHint(text: '还没有投票，点右上角「+」发起一个', icon: Icons.how_to_vote_outlined),
                    ])
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final p in list) _pollCard(p, meId),
                      ],
                    ),
            ),
    );
  }

  Widget _pollCard(Poll p, String? meId) {
    final scheme = Theme.of(context).colorScheme;
    final isMine = p.creatorId == meId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.question,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600)),
                ),
                if (p.closed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('已结束',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${p.creatorName} 发起 · ${p.totalVotes} 人参与${p.closed ? '' : ' · 点击选项投票，再点取消'}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            for (final o in p.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: p.closed ? null : () => _vote(p, o),
                  child: Stack(
                    children: [
                      // 比例条
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FractionallySizedBox(
                          widthFactor: p.totalVotes == 0
                              ? 0
                              : o.count / p.totalVotes,
                          child: Container(
                            height: 38,
                            color: o.votedByMe
                                ? scheme.primary.withValues(alpha: 0.35)
                                : scheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 38,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              if (o.votedByMe)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(Icons.check_circle,
                                      size: 16, color: scheme.primary),
                                ),
                              Expanded(
                                child: Text(o.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5)),
                              ),
                              Text('${o.count} 票',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isMine && !p.closed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _close(p),
                  child: const Text('结束投票', style: TextStyle(fontSize: 12.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
