import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  /// 以「添加账号」方式打开：登录/注册成功后自动返回上一页（不重进主页）。
  final bool addMode;
  const LoginScreen({super.key, this.addMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController();

  /// 服务器注册模式：email（默认）| phone
  String _mode = 'email';
  bool _modeLoaded = false;
  bool _accountMode = false; // true=账号密码 tab
  bool _isRegister = false;
  bool _busy = false;
  bool _showServer = false;

  /// 验证码
  int _codeCountdown = 0;
  Timer? _codeTimer;
  bool _sendingCode = false;

  /// 快捷登录：查到的账号列表 / 选中的账号
  List<User>? _accounts;
  User? _selected;

  static final _phoneRe = RegExp(r'^1[3-9]\d{9}$');
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  bool get _isEmailMode => _mode == 'email';
  String get _phoneDigits => _phone.text.replaceAll(RegExp(r'[^\d]'), '');
  bool get _phoneOk => _phoneRe.hasMatch(_phoneDigits);
  String get _emailText => _email.text.trim().toLowerCase();
  bool get _emailOk => _emailRe.hasMatch(_emailText);
  bool get _identOk => _isEmailMode ? _emailOk : _phoneOk;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_server.text.isEmpty) {
      _server.text = context.read<AppState>().serverBase;
    }
    if (!_modeLoaded) {
      _modeLoaded = true;
      _loadMode();
    }
  }

  Future<void> _loadMode() async {
    try {
      final m = await context.read<AppState>().fetchAuthMode();
      if (mounted) setState(() => _mode = m == 'phone' ? 'phone' : 'email');
    } catch (_) {}
  }

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    _code.dispose();
    _server.dispose();
    _codeTimer?.cancel();
    super.dispose();
  }

  void _resetFlow() {
    _accounts = null;
    _selected = null;
  }

  Future<void> _applyServer(AppState s) async {
    final url = _server.text.trim();
    if (url.isNotEmpty && url != s.serverBase) {
      await s.setServer(url);
    }
  }

  // ---------------- 获取验证码（注册用） ----------------
  Future<void> _sendCode() async {
    final emailMode = _isEmailMode;
    if (emailMode ? !_emailOk : !_phoneOk) {
      showError(context, emailMode ? '请先填写正确的邮箱地址' : '请先填写正确的 11 位手机号');
      return;
    }
    if (_codeCountdown > 0 || _sendingCode) return;
    final s = context.read<AppState>();
    setState(() => _sendingCode = true);
    try {
      await _applyServer(s);
      final res = emailMode
          ? await s.sendEmailCode(_emailText)
          : await s.sendSmsCode(_phoneDigits);
      if (!mounted) return;
      _startCountdown(60);
      if (res.mode == 'dev' && res.devCode != null) {
        _code.text = res.devCode!;
        showError(context, '【开发模式】验证码：${res.devCode}（已自动填入）');
      } else if (res.mode == 'console') {
        showError(context, '【管理员模式】验证码已生成，请联系管理员获取 😊');
      } else {
        showError(context, emailMode ? '验证码已发送，请查收邮箱 📧' : '验证码已发送，请查看短信 📱');
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '发送失败: $e');
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startCountdown(int secs) {
    _codeTimer?.cancel();
    setState(() => _codeCountdown = secs);
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _codeCountdown -= 1;
        if (_codeCountdown <= 0) t.cancel();
      });
    });
  }

  // ---------------- 快捷登录：第一步，查账号 ----------------
  Future<void> _findAccounts() async {
    if (!_identOk) {
      showError(context, _isEmailMode ? '请输入正确的邮箱地址' : '请输入正确的 11 位手机号');
      return;
    }
    final s = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await _applyServer(s);
      final list = _isEmailMode
          ? await s.accounts(email: _emailText)
          : await s.accounts(phone: _phoneDigits);
      if (!mounted) return;
      if (list.isEmpty) {
        showError(
            context,
            _isEmailMode
                ? '该邮箱还没有注册过账号，点下方「立即注册」创建一个吧'
                : '该手机号还没有注册过账号，点下方「立即注册」创建一个吧');
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

  // ---------------- 快捷登录：第三步，登录选中的账号 ----------------
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
      _afterAuthSuccess();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '出错了: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 快捷注册（邮箱 / 手机号 + 验证码） ----------------
  Future<void> _submitQuickRegister() async {
    if (!_identOk) {
      showError(context, _isEmailMode ? '请输入正确的邮箱地址' : '请输入正确的 11 位手机号');
      return;
    }
    final code = _code.text.trim();
    if (code.isEmpty) {
      showError(context, '请先获取并填写验证码');
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
        phone: _isEmailMode ? null : _phoneDigits,
        email: _isEmailMode ? _emailText : null,
        code: code,
      );
      _afterAuthSuccess();
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
      if (!_identOk) {
        showError(context,
            _isEmailMode ? '注册需要绑定邮箱，请填写正确的邮箱地址' : '注册需要绑定手机号，请填写正确的 11 位手机号');
        return;
      }
      if (_code.text.trim().isEmpty) {
        showError(context, '请先获取并填写验证码');
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
          phone: _isEmailMode ? null : _phoneDigits,
          email: _isEmailMode ? _emailText : null,
          code: _code.text.trim(),
        );
      } else {
        await s.login(u, p);
      }
      _afterAuthSuccess();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, '出错了: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 添加账号模式：成功后返回 ----------------
  void _afterAuthSuccess() {
    if (!widget.addMode || !mounted) return;
    Navigator.of(context).pop();
  }

  // ---------------- 构建 ----------------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.addMode ? AppBar(title: const Text('添加账号')) : null,
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
                    segments: [
                      ButtonSegment(
                          value: 'ident',
                          label: Text(_isEmailMode ? '邮箱' : '手机号')),
                      const ButtonSegment(
                          value: 'account', label: Text('账号密码')),
                    ],
                    selected: {_accountMode ? 'account' : 'ident'},
                    onSelectionChanged: _busy
                        ? null
                        : (sel) => setState(() {
                              _accountMode = sel.first == 'account';
                              _resetFlow();
                            }),
                  ),
                  if (!_accountMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _isEmailMode
                            ? '提示：用手机号注册的老账号 → 切到「账号密码」登录（用户名=手机号）'
                            : '提示：用邮箱注册的账号 → 切到「账号密码」登录（用户名=邮箱前缀）',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade400),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ..._fields(),
                  const SizedBox(height: 24),
                  ..._mainActions(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _isRegister = !_isRegister;
                              _resetFlow();
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

    if (_accountMode) {
      // 账号密码模式
      w.add(_usernameField());
      w.add(const SizedBox(height: 14));
      w.add(_passwordField());
      if (_isRegister) {
        w.add(const SizedBox(height: 14));
        w.add(_displayNameField());
        w.add(const SizedBox(height: 14));
        w.add(_isEmailMode
            ? _emailField(label: '邮箱（必填，用于登录和找回）')
            : _phoneField(label: '手机号（必填，用于登录和找回）'));
        w.add(const SizedBox(height: 14));
        w.add(_codeRow());
      }
      return w;
    }

    // 快捷模式
    if (!_isRegister && _accounts != null) {
      if (_selected != null) {
        w.add(_AccountTile(user: _selected!));
        w.add(const SizedBox(height: 14));
        w.add(_passwordField());
      } else {
        w.add(Text(
          _isEmailMode
              ? '该邮箱下有 ${_accounts!.length} 个账号，选择要登录的：'
              : '该手机号下有 ${_accounts!.length} 个账号，选择要登录的：',
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

    w.add(_isEmailMode ? _emailField() : _phoneField());
    if (_isRegister) {
      w.add(const SizedBox(height: 14));
      w.add(_codeRow());
    }
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

    // 账号列表选择状态：不显示主按钮
    if (!_accountMode && !_isRegister && _accounts != null && _selected == null) {
      return w;
    }

    String label;
    Future<void> Function() action;
    if (!_accountMode && !_isRegister && _accounts == null) {
      label = '下一步';
      action = _findAccounts;
    } else if (!_accountMode && !_isRegister) {
      label = '登 录';
      action = _loginSelected;
    } else if (!_accountMode) {
      label = '注 册';
      action = _submitQuickRegister;
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

    if (!_accountMode && !_isRegister && _accounts != null) {
      w.add(TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  if (_selected != null) {
                    _selected = null; // 回到账号列表
                  } else {
                    _resetFlow(); // 回到输入
                  }
                  _password.clear();
                }),
        child: Text(_selected != null
            ? '切换账号'
            : (_isEmailMode ? '← 换个邮箱' : '← 换个手机号')),
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

  Widget _emailField({String label = '邮箱'}) => TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.alternate_email),
          border: const OutlineInputBorder(),
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

  Widget _codeRow() => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '验证码',
                prefixIcon: Icon(Icons.sms_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: (_codeCountdown > 0 || _sendingCode) ? null : _sendCode,
              child: Text(
                _codeCountdown > 0 ? '${_codeCountdown}s' : '获取验证码',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      );
}

/// 快捷登录账号卡片。
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
