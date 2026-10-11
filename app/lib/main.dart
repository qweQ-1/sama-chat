import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/call.dart';
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
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            // 通话来电/呼出全屏页由这里统一弹出（任何页面都能收到来电）
            const CallOverlayHost(),
          ],
        ),
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
    if (s.token == null || s.me == null) return const LoginScreen();
    return isDesktopPlatform ? const DesktopShell() : const HomeScreen();
  }
}
