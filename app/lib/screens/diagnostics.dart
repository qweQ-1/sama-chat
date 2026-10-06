import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../keepalive.dart';
import '../models.dart';
import '../notifications.dart';
import '../store.dart';
import '../widgets.dart';

/// 诊断页：查看通知 / 保活 / 连接状态，发送测试通知。
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Widget _row(String label, String value, {Color? color}) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      trailing: Text(
        value,
        style: TextStyle(
            fontSize: 13, color: color ?? Colors.grey.shade600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final last = s.lastMessageAt;
    return Scaffold(
      appBar: AppBar(title: const Text('诊断')),
      body: ListView(
        children: [
          const SizedBox(height: 6),
          _row('服务器', s.serverBase),
          _row('实时连接 (WebSocket)',
              s.rtConnected ? '已连接 ✓' : '未连接 ✗',
              color: s.rtConnected
                  ? const Color(0xFF22C55E)
                  : Colors.redAccent),
          _row('消息通知开关', s.notificationsEnabled ? '已开启' : '已关闭'),
          _row('后台保活开关', s.keepAliveEnabled ? '已开启' : '已关闭'),
          _row('保活状态', KeepAliveService.debugStatus),
          _row(
            '最近收到消息',
            last == null
                ? '本次会话暂无'
                : formatTime(last.millisecondsSinceEpoch),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: FilledButton.icon(
              onPressed: () async {
                await AppNotifications.requestPermissions();
                await AppNotifications.showMessage(
                  title: '测试通知',
                  body: '看到这条通知 = 通知功能正常 ✓',
                  id: 424242,
                );
                if (context.mounted) {
                  showError(context,
                      '已发送测试通知。没看到？去系统设置检查"萨摩聊天"的通知权限');
                }
              },
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('发送测试通知'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: OutlinedButton.icon(
              onPressed: () {
                context.read<AppState>().rt.ensureConnected();
                setState(() {});
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新状态 / 重连'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final s = context.read<AppState>();
                final sw = Stopwatch()..start();
                String httpText;
                try {
                  await s.api.serverTime();
                  httpText = 'HTTP 连接正常（${sw.elapsedMilliseconds}ms）';
                } on ApiException catch (e) {
                  httpText = 'HTTP 连接失败：${e.message}';
                } catch (e) {
                  httpText = 'HTTP 连接失败：$e';
                }
                s.rt.ensureConnected();
                await Future<void>.delayed(const Duration(seconds: 2));
                if (!context.mounted) return;
                final wsText =
                    s.rt.connected ? 'WebSocket 已连接 ✓' : 'WebSocket 未连接 ✗';
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('网络自检结果'),
                    content: Text(
                      '服务器：${s.serverBase}\n\n$httpText\n$wsText',
                      style: const TextStyle(height: 1.6),
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('好的'),
                      ),
                    ],
                  ),
                );
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.network_check, size: 18),
              label: const Text('网络自检（HTTP + WebSocket）'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '排查提示：\n'
              '• 收不到通知 → 先发"测试通知"，不弹就去系统设置里允许通知\n'
              '• iPhone 后台收不到 → 确认"后台保活"已开启，且 App 没有被上滑划掉\n'
              '• Android 收不到 → 系统设置里给"萨摩聊天"开启自启动、关闭电池优化\n'
              '• 连接断开 → 点"刷新状态 / 重连"',
              style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
