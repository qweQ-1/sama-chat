import 'dart:io';

import 'package:flutter/foundation.dart';

/// App-wide configuration.
class AppConfig {
  /// Default server address baked into the build.
  /// 可被构建参数覆盖：flutter build --dart-define=SAMA_SERVER=...
  /// 也可在 App 内「我 → 服务器设置」随时修改。
  static const String defaultServer = String.fromEnvironment(
    'SAMA_SERVER',
    defaultValue: 'https://samachat.de5.net',
  );

  static const String appName = '萨摩聊天';
}

/// 是否为桌面平台（Windows / macOS / Linux）。
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

bool? _mfChecked;
bool? _mfAvailable;

/// Windows 是否具备 Media Foundation（视频播放组件）。
/// Server 精简版 / N 版系统缺失时：提前拦截，避免调用播放器导致进程崩溃。
bool get mediaFoundationAvailable {
  if (kIsWeb || !Platform.isWindows) return true;
  if (_mfChecked == true) return _mfAvailable!;
  _mfChecked = true;
  try {
    final hasMfplat =
        File(r'C:\Windows\System32\mfplat.dll').existsSync();
    final hasMf = File(r'C:\Windows\System32\mf.dll').existsSync();
    _mfAvailable = hasMfplat && hasMf;
  } catch (_) {
    _mfAvailable = true; // 检测失败不拦截，交给运行时兜底
  }
  return _mfAvailable!;
}
