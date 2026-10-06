/// 自动更新：
/// - 检查 GitHub Releases 最新版本（原链接，不经过任何加速服务）
/// - Android：下载 APK（带进度 + 可取消）→ 自动拉起系统安装器
/// - iOS：跳转到浏览器打开 Release 页面（自签安装流程）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _repo = 'qweQ-1/sama-chat';
const _latestApi = 'https://api.github.com/repos/$_repo/releases/latest';

class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;
  final String? apkUrl;
  final String? ipaUrl;

  UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.ipaUrl,
  });
}

class Updater {
  static String _cachedVersion = '';

  /// 当前安装版本（来自构建时的 pubspec 版本号）
  static Future<String> currentVersion() async {
    if (_cachedVersion.isNotEmpty) return _cachedVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedVersion = info.version;
    } catch (_) {
      _cachedVersion = '0.0.0';
    }
    return _cachedVersion;
  }

  /// 检查更新：有新版本返回 UpdateInfo，否则返回 null。
  static Future<UpdateInfo?> check() async {
    try {
      final res = await http
          .get(
            Uri.parse(_latestApi),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      if (tag.isEmpty) return null;
      final current = await currentVersion();
      if (_compare(tag, current) <= 0) return null;

      String? apk;
      String? ipa;
      for (final a in (j['assets'] as List? ?? const <dynamic>[])) {
        if (a is! Map) continue;
        final name = a['name'] as String? ?? '';
        final url = a['browser_download_url'] as String?;
        if (url == null) continue;
        if (name.endsWith('.apk')) apk = url;
        if (name.endsWith('.ipa')) ipa = url;
      }
      return UpdateInfo(
        version: tag,
        notes: (j['body'] as String? ?? '').trim(),
        pageUrl: j['html_url'] as String? ??
            'https://github.com/$_repo/releases/latest',
        apkUrl: apk,
        ipaUrl: ipa,
      );
    } catch (_) {
      return null;
    }
  }

  /// 自动检查节流：6 小时内只自动检查一次。
  static Future<bool> shouldAutoCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('lastUpdateCheck') ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - last < 6 * 60 * 60 * 1000) return false;
      await prefs.setInt('lastUpdateCheck', nowMs);
      return true;
    } catch (_) {
      return true;
    }
  }

  /// 版本比较：a > b 返回 1。
  static int _compare(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}

/// 弹出更新对话框。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 v${info.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: Text(
            info.notes.isEmpty ? '有新的更新可用，建议升级。' : info.notes,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            startUpdate(context, info);
          },
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}

/// 执行更新：桌面 / iOS 跳浏览器 / Android 下载并拉起安装器。
Future<void> startUpdate(BuildContext context, UpdateInfo info) async {
  if (Platform.isIOS || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      final ok = await launchUrl(
        Uri.parse(info.pageUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (context.mounted) {
        _toast(context, '无法打开浏览器，请手动访问 GitHub Releases 下载更新');
      }
    }
    return;
  }

  // -------- Android --------
  final apkUrl = info.apkUrl;
  if (apkUrl == null) {
    try {
      await launchUrl(Uri.parse(info.pageUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    return;
  }

  final progress = ValueNotifier<double>(0);
  var cancelled = false;
  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('正在下载更新包…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: v > 0 ? v : null),
            const SizedBox(height: 10),
            Text(
              v > 0 ? '${(v * 100).toStringAsFixed(0)}%' : '正在连接 GitHub…',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text('使用 GitHub 原链接下载',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            dialogOpen = false;
            Navigator.pop(ctx);
          },
          child: const Text('取消'),
        ),
      ],
    ),
  );

  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/SamaChat-${info.version}.apk');
    final client = http.Client();
    final req = http.Request('GET', Uri.parse(apkUrl));
    final res = await client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final total = res.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in res.stream) {
      if (cancelled) {
        await sink.close();
        try {
          await file.delete();
        } catch (_) {}
        client.close();
        return;
      }
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) progress.value = received / total;
    }
    await sink.close();
    client.close();
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.pop(context);
    }
    final result = await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done && context.mounted) {
      _toast(context, '安装器打开失败（${result.message}），请到 GitHub Releases 手动下载');
    }
  } catch (e) {
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.pop(context);
    }
    if (context.mounted) {
      _toast(context, '下载失败：$e（可到 GitHub Releases 手动下载）');
    }
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}
