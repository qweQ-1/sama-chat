/// App-wide configuration.
class AppConfig {
  /// Default server address. Overridable at build time:
  ///   flutter build apk --dart-define=SAMA_SERVER=https://example.com
  /// and at runtime in 我 → 服务器设置.
  static const String defaultServer = String.fromEnvironment(
    'SAMA_SERVER',
    defaultValue: 'http://127.0.0.1:8080',
  );

  static const String appName = '萨摩聊天';
}
