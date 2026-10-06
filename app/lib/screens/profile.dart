import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../config.dart';
import '../store.dart';
import '../widgets.dart';
import 'diagnostics.dart';
import 'blocklist.dart';
import '../updater.dart';

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

  Future<void> _bindPhone(BuildContext context) async {
    final s = context.read<AppState>();
    final result = await showDialog<({String phone, String code})>(
      context: context,
      builder: (_) => const _BindPhoneDialog(),
    );
    if (result == null) return;
    try {
      await s.bindPhone(result.phone, result.code);
      if (context.mounted) showError(context, '手机号已绑定 ✓');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  Future<void> _bindEmail(BuildContext context) async {
    final s = context.read<AppState>();
    final result = await showDialog<({String email, String code})>(
      context: context,
      builder: (_) => const _BindEmailDialog(),
    );
    if (result == null) return;
    try {
      await s.bindEmail(result.email, result.code);
      if (context.mounted) showError(context, '邮箱已绑定 ✓');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  static String _intervalLabel(int m) {
    if (m <= 0) return '后台自动检查已关闭';
    if (m < 60) return '每 $m 分钟检查一次';
    if (m % 60 == 0) return '每 ${m ~/ 60} 小时检查一次';
    return '每 $m 分钟检查一次';
  }

  void _pickUpdateInterval(BuildContext context) {
    final s = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    const options = [30, 60, 120, 360, 720, 0];
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('自动检查更新间隔'),
        children: options
            .map((m) => ListTile(
                  dense: true,
                  title: Text(m == 0 ? '关闭后台自动检查' : _intervalLabel(m)),
                  trailing: m == s.updateIntervalMinutes
                      ? Icon(Icons.check, color: scheme.primary)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await s.setUpdateInterval(m);
                    if (context.mounted) {
                      showError(context, '已设置：${_intervalLabel(m)}');
                    }
                  },
                ))
            .toList(),
      ),
    );
  }

  static String _maskPhone(String p) =>
      p.length == 11 ? '${p.substring(0, 3)}****${p.substring(7)}' : p;

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
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: const Text('手机号'),
            subtitle: Text(
              (me?.phone.isEmpty ?? true)
                  ? '未绑定 · 点这里绑定手机号'
                  : _maskPhone(me!.phone),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _bindPhone(context),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('邮箱'),
            subtitle: Text(
              (me?.email.isEmpty ?? true) ? '未绑定 · 点这里绑定邮箱' : me!.email,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _bindEmail(context),
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
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            subtitle: const Text('自动识别平台，从 GitHub 获取最新版本',
                style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              showError(context, '正在检查更新…');
              final info = await Updater.check();
              if (!context.mounted) return;
              if (info == null) {
                showError(context, '已是最新版本 ✓');
              } else {
                showUpdateDialog(context, info);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('自动检查更新'),
            subtitle: Text(
              '每次进入自动检查 · ${_intervalLabel(s.updateIntervalMinutes)}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickUpdateInterval(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('${AppConfig.appName} v2.2.2',
                style: TextStyle(fontSize: 12)),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: '2.2.2',
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

/// 绑定手机号对话框：手机号 + 短信验证码。
class _BindPhoneDialog extends StatefulWidget {
  const _BindPhoneDialog();

  @override
  State<_BindPhoneDialog> createState() => _BindPhoneDialogState();
}

class _BindPhoneDialogState extends State<_BindPhoneDialog> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  int _countdown = 0;
  Timer? _timer;
  bool _sending = false;
  static final _re = RegExp(r'^1[3-9]\d{9}$');

  String get _digits => _phone.text.replaceAll(RegExp(r'[^\d]'), '');

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_re.hasMatch(_digits)) {
      showError(context, '请先填写正确的 11 位手机号');
      return;
    }
    if (_countdown > 0 || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await context.read<AppState>().sendSmsCode(_digits);
      if (!mounted) return;
      _startCountdown(60);
      if (res.mode == 'dev' && res.devCode != null) {
        _code.text = res.devCode!;
        showError(context, '【开发模式】验证码：${res.devCode}（已自动填入）');
      } else if (res.mode == 'console') {
        showError(context, '【管理员模式】验证码已生成，请联系管理员获取 😊');
      } else {
        showError(context, '验证码已发送，请查看短信 📱');
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发送失败: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown(int secs) {
    _timer?.cancel();
    setState(() => _countdown = secs);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown -= 1;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('绑定手机号'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '手机号',
              hintText: '11 位手机号',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: (_countdown > 0 || _sending) ? null : _send,
                child: Text(
                  _countdown > 0 ? '${_countdown}s' : '获取验证码',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final p = _digits;
            final c = _code.text.trim();
            if (!_re.hasMatch(p)) {
              showError(context, '请输入正确的 11 位手机号');
              return;
            }
            if (c.isEmpty) {
              showError(context, '请输入短信验证码');
              return;
            }
            Navigator.pop(context, (phone: p, code: c));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 绑定邮箱对话框：邮箱 + 邮箱验证码。
class _BindEmailDialog extends StatefulWidget {
  const _BindEmailDialog();

  @override
  State<_BindEmailDialog> createState() => _BindEmailDialogState();
}

class _BindEmailDialogState extends State<_BindEmailDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  int _countdown = 0;
  Timer? _timer;
  bool _sending = false;
  static final _re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  String get _norm => _email.text.trim().toLowerCase();

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_re.hasMatch(_norm)) {
      showError(context, '请先填写正确的邮箱地址');
      return;
    }
    if (_countdown > 0 || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await context.read<AppState>().sendEmailCode(_norm);
      if (!mounted) return;
      _startCountdown(60);
      if (res.mode == 'dev' && res.devCode != null) {
        _code.text = res.devCode!;
        showError(context, '【开发模式】验证码：${res.devCode}（已自动填入）');
      } else if (res.mode == 'console') {
        showError(context, '【管理员模式】验证码已生成，请联系管理员获取 😊');
      } else {
        showError(context, '验证码已发送，请查收邮箱 📧');
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发送失败: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown(int secs) {
    _timer?.cancel();
    setState(() => _countdown = secs);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown -= 1;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('绑定邮箱'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '邮箱',
              hintText: '例如 name@qq.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: (_countdown > 0 || _sending) ? null : _send,
                child: Text(
                  _countdown > 0 ? '${_countdown}s' : '获取验证码',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final e = _norm;
            final c = _code.text.trim();
            if (!_re.hasMatch(e)) {
              showError(context, '请输入正确的邮箱地址');
              return;
            }
            if (c.isEmpty) {
              showError(context, '请输入验证码');
              return;
            }
            Navigator.pop(context, (email: e, code: c));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
