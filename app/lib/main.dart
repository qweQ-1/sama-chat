import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/desktop.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'store.dart';

void main() {
  runApp(const SamaChatApp());
}

const kBrand = Color(0xFF5B5BD6);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF7F7FB)
        : null,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: brightness == Brightness.light ? Colors.white : null,
      foregroundColor: brightness == Brightness.light ? Colors.black87 : null,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class SamaChatApp extends StatelessWidget {
  const SamaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..boot(),
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const RootGate(),
      ),
    );
  }
}

/// Decides between login and the main shell.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (s.token == null || s.me == null) {
      // 有登录态但还没连上服务器 → 显示"正在连接"过渡页，不要直接甩去登录
      if (s.token != null) return const _RestoringScreen();
      return const LoginScreen();
    }
    return isDesktopPlatform ? const DesktopShell() : const HomeScreen();
  }
}

/// 登录态还在、但服务器暂时连不上时的过渡页（网络恢复后自动进入）。
class _RestoringScreen extends StatelessWidget {
  const _RestoringScreen();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.restoreFailed)
                  const Icon(Icons.cloud_off_outlined,
                      size: 56, color: Colors.grey)
                else
                  const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  s.restoreFailed
                      ? '连接不上服务器\n请检查手机网络后重试'
                      : '正在连接服务器…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade600,
                      height: 1.6),
                ),
                const SizedBox(height: 22),
                if (s.restoreFailed)
                  FilledButton.icon(
                    onPressed: () =>
                        context.read<AppState>().retryRestoreSession(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.read<AppState>().logout(),
                  child: const Text('重新登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
