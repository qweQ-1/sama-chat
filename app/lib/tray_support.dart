/// Windows 桌面托盘常驻：
/// - 点 X / 最小化 → 收进托盘（不退出，后台收消息）
/// - 托盘菜单：显示主界面 / 退出
/// - 有新消息 → 图标闪动 + 红点徽章 + tooltip 未读数
///
/// 仅在桌面平台启用（移动端此文件逻辑不执行）。
// ignore_for_file: deprecated_member_use
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'store.dart';

class TraySupport with TrayListener, WindowListener {
  static final TraySupport _i = TraySupport._();
  TraySupport._();
  static TraySupport get instance => _i;

  AppState? _state;
  bool _inited = false;
  String? _normalIcon;
  String? _alertIcon;
  bool _alert = false;
  int _lastUnread = 0;
  Timer? _flashTimer;

  bool get _supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> init(AppState state) async {
    if (_inited || !_supported) return;
    _inited = true;
    _state = state;

    // 图标：asset → 临时文件（托盘需要文件路径）
    try {
      final dir = await getTemporaryDirectory();
      _normalIcon = '${dir.path}/sama_tray.ico';
      _alertIcon = '${dir.path}/sama_tray_alert.ico';
      final n = await rootBundle.load('assets/tray/tray.ico');
      await File(_normalIcon!).writeAsBytes(n.buffer.asUint8List());
      final a = await rootBundle.load('assets/tray/tray_alert.ico');
      await File(_alertIcon!).writeAsBytes(a.buffer.asUint8List());
    } catch (_) {
      return; // 图标失败不影响 App
    }

    // 关窗拦截（点 X → 隐藏到托盘）
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    // 托盘
    trayManager.addListener(this);
    await trayManager.setIcon(_normalIcon!);
    await trayManager.setToolTip('萨摩聊天');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: '显示主界面'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '退出萨摩聊天'),
    ]));

    // 监听未读变化
    state.addListener(_onState);
    _onState();
  }

  // ---------------------------------------------------------------- 状态
  void _onState() {
    final s = _state;
    if (s == null || _normalIcon == null) return;
    final unread = s.conversations.fold<int>(0, (a, c) => a + c.unread);
    if (unread == _lastUnread) return;
    final had = _lastUnread > 0;
    _lastUnread = unread;

    unawaited(trayManager.setToolTip(
        unread > 0 ? '萨摩聊天 · $unread 条新消息' : '萨摩聊天'));

    if (unread > 0 && !had) {
      _flash();
    } else if (unread == 0) {
      _alert = false;
      unawaited(trayManager.setIcon(_normalIcon!));
    }
  }

  /// 新消息闪动 3 次，然后停在红点图标。
  void _flash() {
    _flashTimer?.cancel();
    var ticks = 0;
    _flashTimer = Timer.periodic(const Duration(milliseconds: 450), (t) {
      ticks++;
      _alert = !_alert;
      unawaited(trayManager.setIcon((_alert ? _alertIcon : _normalIcon)!));
      if (ticks >= 6) {
        t.cancel();
        _alert = true;
        unawaited(trayManager.setIcon(_alertIcon!));
      }
    });
  }

  // ---------------------------------------------------------------- 托盘事件
  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') _showWindow();
    if (menuItem.key == 'exit') _exit();
  }

  // ---------------------------------------------------------------- 窗口事件
  @override
  void onWindowClose() async {
    // 不是真退出：收进托盘
    await windowManager.hide();
  }

  @override
  void onWindowMinimize() async {
    await windowManager.hide();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exit() async {
    _flashTimer?.cancel();
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
  }
}
