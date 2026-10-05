import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _server = TextEditingController();
  bool _isRegister = false;
  bool _phoneMode = true; // true=手机号, false=账号密码
  bool _busy = false;
  bool _showServer = false;

  /// 手机号登录：查到的账号列表 / 选中的账号。
  List<User>? _accounts;
  User? _selected;

  static final _phoneRe = RegExp(r'^1[3-9]\d{9}$');

  String get _phoneDigits => _phone.text.replaceAll(RegExp(r'[^\d]'), '');
  bool get _phoneOk => _phoneRe.hasMatch(_phoneDigits);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_server.text.isEmpty) {
      _server.text = context.read<AppState>().serverBase;
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    _server.dispose();
    super.dispose();
  }

  void _resetPhoneFlow() {
    _accounts = null;
    _selected = null;
  }

  Future<void> _applyServer(AppState s) async {
    final url = _server.text.trim();
    if (url.isNotEmpty && url != s.serverBase) {
      await s.setServer(url);
    }
  }

  // ---------------- 手机号登录：第一步，查账号 ----------------
  Future<void> _findAccounts() async {
    if (!_phoneOk) {
      showError(context, '请输入正确的 11 位手机号');
      return;
    }
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await _applyServer(s);
      final list = await s.accountsByPhone(_phoneDigits);
      if (!mounted) return;
      if (list.isEmpty) {
        showError(context, '该手机号还没有注册过账号，点下方「立即注册」创建一个吧');
        return;
      }
      setState(() {
        _accounts = list;
        _selected = list.length == 1 ? list.first : null;
        _password.clear();
      });
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '出错了: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 手机号登录：第三步，登录选中的账号 ----------------
  Future<void> _loginSelected() async {
    final sel = _selected;
    if (sel == null) return;
    if (_password.text.isEmpty) {
      showError(context, '请输入密码');
      return;
    }
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await _applyServer(s);
      await s.login(sel.username, _password.text);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '出错了: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 手机号注册（自动生成用户名） ----------------
  Future<void> _submitPhoneRegister() async {
    if (!_phoneOk) {
      showError(context, '请输入正确的 11 位手机号');
      return;
    }
    if (_password.text.length < 6) {
      showError(context, '密码至少 6 位');
      return;
    }
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await _applyServer(s);
      final dn = _displayName.text.trim();
      await s.register(
        password: _password.text,
        displayName: dn.isEmpty ? null : dn,
        phone: _phoneDigits,
      );
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '出错了: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 账号密码 登录 / 注册 ----------------
  Future<void> _submitAccount() async {
    final u = _username.text.trim();
    final p = _password.text;
    if (u.isEmpty) {
      showError(context, '请填写用户名');
      return;
    }
    if (_isRegister) {
      if (p.length < 6) {
        showError(context, '密码至少 6 位');
        return;
      }
      if (!_phoneOk) {
        showError(context, '注册需要绑定手机号，请填写正确的 11 位手机号');
        return;
      }
    } else if (p.isEmpty) {
      showError(context, '请填写用户名和密码');
      return;
    }
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await _applyServer(s);
      if (_isRegister) {
        final dn = _displayName.text.trim();
        await s.register(
          username: u,
          password: p,
          displayName: dn.isEmpty ? null : dn,
          phone: _phoneDigits,
        );
      } else {
        await s.login(u, p);
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '出错了: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 构建 ----------------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text('萨',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '私聊 · 群聊 · 视频 · 炫圈',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'phone', label: Text('手机号')),
                      ButtonSegment(value: 'account', label: Text('账号密码')),
                    ],
                    selected: {_phoneMode ? 'phone' : 'account'},
                    onSelectionChanged: _busy
                        ? null
                        : (sel) => setState(() {
                              _phoneMode = sel.first == 'phone';
                              _resetPhoneFlow();
                            }),
                  ),
                  const SizedBox(height: 22),
                  ..._fields(),
                  const SizedBox(height: 24),
                  ..._mainActions(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _isRegister = !_isRegister;
                              _resetPhoneFlow();
                            }),
                    child: Text(_isRegister ? '已有账号？去登录' : '没有账号？立即注册'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _showServer = !_showServer),
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: Text(_showServer ? '收起服务器设置' : '服务器设置',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  if (_showServer)
                    TextField(
                      controller: _server,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: 'https://your-server.example.com',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    final w = <Widget>[];

    if (!_phoneMode) {
      // 账号密码模式
      w.add(_usernameField());
      w.add(const SizedBox(height: 14));
      w.add(_passwordField());
      if (_isRegister) {
        w.add(const SizedBox(height: 14));
        w.add(_displayNameField());
        w.add(const SizedBox(height: 14));
        w.add(_phoneField(label: '手机号（必填，用于登录和找回）'));
      }
      return w;
    }

    // 手机号模式
    if (!_isRegister && _accounts != null) {
      if (_selected != null) {
        // 已选中账号 → 输密码
        w.add(_AccountTile(user: _selected!));
        w.add(const SizedBox(height: 14));
        w.add(_passwordField());
      } else {
        // 多账号 → 列表选择
        w.add(Text(
          '该手机号下有 ${_accounts!.length} 个账号，选择要登录的：',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ));
        w.add(const SizedBox(height: 12));
        for (final a in _accounts!) {
          w.add(_AccountTile(
            user: a,
            onTap: () => setState(() {
              _selected = a;
              _password.clear();
            }),
          ));
        }
      }
      return w;
    }

    w.add(_phoneField());
    w.add(const SizedBox(height: 14));
    w.add(_passwordField());
    if (_isRegister) {
      w.add(const SizedBox(height: 14));
      w.add(_displayNameField());
    }
    return w;
  }

  List<Widget> _mainActions() {
    final w = <Widget>[];

    // 账号列表选择状态：不放主按钮，由下方文字按钮控制返回
    if (_phoneMode && !_isRegister && _accounts != null && _selected == null) {
      return w;
    }

    String label;
    Future<void> Function() action;
    if (_phoneMode && !_isRegister && _accounts == null) {
      label = '下一步';
      action = _findAccounts;
    } else if (_phoneMode && !_isRegister) {
      label = '登 录';
      action = _loginSelected;
    } else if (_phoneMode) {
      label = '注 册';
      action = _submitPhoneRegister;
    } else {
      label = _isRegister ? '注 册' : '登 录';
      action = _submitAccount;
    }

    w.add(FilledButton(
      onPressed: _busy ? null : action,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 15),
      ),
      child: _busy
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label, style: const TextStyle(fontSize: 16)),
    ));

    if (_phoneMode && !_isRegister && _accounts != null) {
      w.add(TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  if (_selected != null) {
                    _selected = null; // 回到账号列表
                  } else {
                    _resetPhoneFlow(); // 回到手机号输入
                  }
                  _password.clear();
                }),
        child: Text(_selected != null ? '切换账号' : '← 换个手机号'),
      ));
    }
    return w;
  }

  Widget _usernameField() => TextField(
        controller: _username,
        decoration: const InputDecoration(
          labelText: '用户名',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
        ),
        autocorrect: false,
        enableSuggestions: false,
      );

  Widget _phoneField({String label = '手机号'}) => TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.phone_iphone),
          border: const OutlineInputBorder(),
        ),
        autocorrect: false,
      );

  Widget _passwordField() => TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '密码',
          prefixIcon: Icon(Icons.lock_outline),
          border: OutlineInputBorder(),
        ),
      );

  Widget _displayNameField() => TextField(
        controller: _displayName,
        decoration: const InputDecoration(
          labelText: '昵称（可留空）',
          prefixIcon: Icon(Icons.badge_outlined),
          border: OutlineInputBorder(),
        ),
      );
}

/// 手机号下的账号卡片（选择登录用）。
class _AccountTile extends StatelessWidget {
  final User user;
  final VoidCallback? onTap;
  const _AccountTile({required this.user, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Avatar(name: user.displayName, url: user.avatar, size: 40),
        title: Text(user.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text('@${user.username}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        trailing: onTap != null
            ? const Icon(Icons.chevron_right)
            : Icon(Icons.check_circle_outline, color: scheme.primary),
      ),
    );
  }
}
