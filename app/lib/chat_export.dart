/// 聊天记录导出：拉取会话全量消息 → 生成自包含 HTML → 保存/分享。
///
/// 桌面端：保存到「下载」目录并返回文件路径（用系统浏览器打开即可阅读）。
/// 移动端：写入临时文件后拉起系统分享面板（可存入「文件」App / 发给自己）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';
import 'store.dart';

/// 导出单个会话的全部聊天记录，返回生成的文件。
Future<File> exportChatHistory(AppState s, Conversation conv) async {
  final html = await buildChatHtml(s, conv);

  final safeName = conv.name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim()
      .isEmpty
      ? 'chat'
      : conv.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final date = DateTime.now();
  final stamp =
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  final fileName = '萨摩聊天-$safeName-$stamp.html';

  final tmpDir = await getTemporaryDirectory();
  final tmpFile = File('${tmpDir.path}/$fileName');
  await tmpFile.writeAsString(html, flush: true);

  if (isDesktopPlatform) {
    // 桌面：直接放进「下载」文件夹（找不到就用文档目录）
    Directory? dl;
    try {
      dl = await getDownloadsDirectory();
    } catch (_) {}
    dl ??= await getApplicationDocumentsDirectory();
    final out = File('${dl.path}/$fileName');
    await out.writeAsString(html, flush: true);
    return out;
  }

  // 移动端：系统分享面板（用户可存到文件 App / 发给自己备份）
  await Share.shareXFiles(
    [XFile(tmpFile.path, mimeType: 'text/html')],
    subject: '${conv.name} 聊天记录',
  );
  return tmpFile;
}

/// 拉全量消息（分页循环，上限 5000 条防呆）并生成 HTML。
Future<String> buildChatHtml(AppState s, Conversation conv) async {
  const pageSize = 200;
  const hardLimit = 5000;
  final all = <Message>[];
  var before = DateTime.now().millisecondsSinceEpoch + 1;
  while (all.length < hardLimit) {
    final batch =
        await s.api.messagesBefore(conv.id, before: before, limit: pageSize);
    if (batch.isEmpty) break;
    all.insertAll(0, batch);
    final oldest = batch.first.createdAt;
    if (oldest >= before) break; // 防死循环
    before = oldest;
    if (batch.length < pageSize) break;
  }

  final sb = StringBuffer();
  sb.writeln('<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">');
  sb.writeln('<meta name="viewport" content="width=device-width,initial-scale=1">');
  sb.writeln('<title>${_esc(conv.name)} · 聊天记录</title>');
  sb.writeln('<style>');
  sb.writeln('''
body{font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;background:#f2f2f6;margin:0;padding:16px;}
h1{font-size:18px;text-align:center;color:#333;margin:8px 0;}
.sub{text-align:center;color:#999;font-size:12px;margin-bottom:20px;}
.msg{display:flex;margin:6px 0;}
.msg.right{justify-content:flex-end;}
.bubble{max-width:70%;background:#fff;border-radius:12px;padding:8px 12px;box-shadow:0 1px 2px rgba(0,0,0,.05);word-break:break-word;}
.msg.right .bubble{background:#d9e4ff;}
.meta{font-size:11px;color:#999;margin-bottom:3px;}
.media{max-width:100%;border-radius:8px;margin-top:4px;}
.recalled{color:#aaa;font-style:italic;}
a{color:#4c6ef5;text-decoration:none;word-break:break-all;}
.footer{text-align:center;color:#bbb;font-size:11px;margin:24px 0 8px;}
''');
  sb.writeln('</style></head><body>');
  sb.writeln('<h1>${_esc(conv.name)}</h1>');
  sb.writeln(
      '<div class="sub">共 ${all.length} 条消息 · 导出于 ${_fmtFull(DateTime.now().millisecondsSinceEpoch)}</div>');

  for (final m in all) {
    final mine = m.senderId == s.me?.id;
    final sender = _senderName(s, conv, m);
    sb.writeln('<div class="msg${mine ? ' right' : ''}">');
    sb.writeln('<div class="bubble">');
    sb.writeln(
        '<div class="meta">${_esc(sender)} · ${_fmtFull(m.createdAt)}</div>');
    if (m.recalled) {
      sb.writeln('<span class="recalled">[已撤回]</span>');
    } else {
      sb.writeln(_renderBody(s, m));
    }
    sb.writeln('</div></div>');
  }
  sb.writeln(
      '<div class="footer">由 萨摩聊天 导出 · 图片/语音/文件需联网查看</div>');
  sb.writeln('</body></html>');
  return sb.toString();
}

String _renderBody(AppState s, Message m) {
  switch (m.type) {
    case 'image':
      return '<img class="media" src="${_esc(_abs(s, m.content))}" loading="lazy">';
    case 'video':
      return '<video class="media" controls preload="metadata" src="${_esc(_abs(s, m.content))}"></video>';
    case 'sticker':
      return '<img class="media" style="max-width:120px" src="${_esc(_abs(s, m.content))}">';
    case 'voice':
      final sec = m.duration;
      return '🎤 语音 ${sec}″<br><audio controls preload="none" src="${_esc(_abs(s, m.content))}"></audio>';
    case 'file':
      final name = m.fileName.isEmpty ? '文件' : m.fileName;
      final size = m.fileSize > 0 ? '（${_fmtSize(m.fileSize)}）' : '';
      return '📎 <a href="${_esc(_abs(s, m.content))}">${_esc(name)}</a>$size';
    default:
      return _esc(m.content).replaceAll('\n', '<br>');
  }
}

String _senderName(AppState s, Conversation conv, Message m) {
  if (m.senderId == s.me?.id) return '我';
  if (!conv.isGroup) return conv.name;
  final f = s.friends.where((u) => u.id == m.senderId).cast<User?>().firstOrNull;
  return f?.displayName ?? m.senderId;
}

String _abs(AppState s, String url) =>
    url.startsWith('http') ? url : '${s.serverBase}$url';

String _esc(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _fmtFull(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

String _fmtSize(int bytes) {
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// 弹出导出进度对话框并执行导出；返回结果文案。
Future<String> runExportFlow(BuildContext context, AppState s, Conversation conv) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(strokeWidth: 2.5),
          SizedBox(width: 16),
          Expanded(child: Text('正在导出聊天记录…')),
        ],
      ),
    ),
  );
  try {
    final file = await exportChatHistory(s, conv);
    if (context.mounted) Navigator.pop(context); // 关进度
    if (isDesktopPlatform) {
      return '已导出到：${file.path}';
    }
    return '已生成导出文件，可在分享面板中保存';
  } catch (e) {
    if (context.mounted) Navigator.pop(context);
    rethrow;
  }
}
