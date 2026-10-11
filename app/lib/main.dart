import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/call.dart';
import 'screens/desktop.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'store.dart';
import 'tray_support.dart';

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
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            // 通话来电/呼出全屏页由这里统一弹出（任何页面都能收到来电）
            const CallOverlayHost(),
            // Windows 桌面：托盘常驻（点 X 收进托盘，新消息闪动红点）
            const TrayHost(),
          ],
        ),
        home: const RootGate(),
      ),
    );
  }
}

/// 桌面托盘初始化宿主（只渲染逻辑，不占空间）。
class TrayHost extends StatefulWidget {
  const TrayHost({super.key});

  @override
  State<TrayHost> createState() => _TrayHostState();
}

class _TrayHostState extends State<TrayHost> {
  @override
  void initState() {
    super.initState();
    if (!isDesktopPlatform) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TraySupport.instance.init(context.read<AppState>());
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
    if (s.token == null || s.me == null) return const LoginScreen();
    return isDesktopPlatform ? const DesktopShell() : const HomeScreen();
  }
}
