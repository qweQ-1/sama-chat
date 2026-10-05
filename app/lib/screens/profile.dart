import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../config.dart';
import '../store.dart';
import '../widgets.dart';
import 'diagnostics.dart';
import 'blocklist.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  Future<void> _changeAvatar(BuildContext context) async {
    final s = context.read<AppState>();
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final url = await s.api.uploadImage(bytes, ext);
      await s.updateProfile(avatar: url);
      if (context.mounted) showError(context, '头像已更新 ✅');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    } catch (e) {
      if (context.mounted) showError(context, '更新头像失败: $e');
    }
  }

  void _editName(BuildContext context) {
    final s = context.read<AppState>();
    final controller = TextEditingController(text: s.me?.displayName ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改昵称'),
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
            onPressed: () async {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              if (name.isEmpty) return;
              try {
                await s.updateProfile(displayName: name);
              } on ApiException catch (e) {
                if (context.mounted) showError(context, e.message);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _serverSettings(BuildContext context) {
    final s = context.read<AppState>();
    final controller = TextEditingController(text: s.serverBase);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('服务器设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'https://your-server.example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 10),
            const Text('修改服务器地址后需要重新登录。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await s.setServer(controller.text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _changeAvatar(context),
                  child: Stack(
                    children: [
                      Avatar(name: me?.displayName ?? '?', url: me?.avatar, size: 88),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(me?.displayName ?? '',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('@${me?.username ?? ''}',
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      s.rtConnected ? Icons.bolt : Icons.bolt_outlined,
                      size: 14,
                      color: s.rtConnected
                          ? const Color(0xFF22C55E)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.rtConnected ? '实时连接正常' : '实时连接断开',
                      style: TextStyle(
                          fontSize: 12,
                          color: s.rtConnected
                              ? const Color(0xFF22C55E)
                              : Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('修改昵称'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editName(context),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('更换头像'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _changeAvatar(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('消息通知'),
            subtitle: const Text('收到新消息时弹出通知',
                style: TextStyle(fontSize: 12)),
            value: s.notificationsEnabled,
            onChanged: (v) => s.setNotifications(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_tethering),
            title: const Text('后台保活'),
            subtitle: const Text('App 退到后台后仍保持在线收消息（会增加少量耗电）',
                style: TextStyle(fontSize: 12)),
            value: s.keepAliveEnabled,
            onChanged: (v) => s.setKeepAlive(v),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器设置'),
            subtitle: Text(s.serverBase,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _serverSettings(context),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('黑名单'),
            subtitle: const Text('查看和解除拉黑的用户', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BlockListScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('诊断'),
            subtitle: const Text('通知 / 保活 / 连接状态自检 + 测试通知',
                style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('${AppConfig.appName} v1.3.1',
                style: TextStyle(fontSize: 12)),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: '1.3.1',
              children: const [
                Text('一个轻量的实时聊天应用：私聊、群聊、炫圈、面对面扫码加好友。'),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(24),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('退出登录'),
                  content: const Text('确定要退出当前账号吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () {
                        Navigator.pop(ctx);
                        s.logout();
                      },
                      child: const Text('退出'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }
}
