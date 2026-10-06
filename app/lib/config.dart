import 'dart:io';

import 'package:flutter/foundation.dart';

/// App-wide configuration.
class AppConfig {
  /// Default server address baked into the build.
  /// 可被构建参数覆盖：flutter build --dart-define=SAMA_SERVER=...
  /// 也可在 App 内「我 → 服务器设置」随时修改。
  static const String defaultServer = String.fromEnvironment(
    'SAMA_SERVER',
    defaultValue: 'https://refrain-tapping-crazy.ngrok-free.dev',
  );

  static const String appName = '萨摩聊天';
}

/// 是否为桌面平台（Windows / macOS / Linux）。
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
