import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat.dart';

/// "My QR code" — the other person scans this to add me.
class MyQrScreen extends StatefulWidget {
  const MyQrScreen({super.key});

  @override
  State<MyQrScreen> createState() => _MyQrScreenState();
}

class _MyQrScreenState extends State<MyQrScreen> {
  String? _payload;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<AppState>().api.myQrPayload();
      if (mounted) setState(() => _payload = p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    return Scaffold(
      backgroundColor: const Color(0xFF2B2B3C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('我的二维码'),
        elevation: 0,
      ),
      body: Center(
        child: _error != null
            ? Text('加载失败: $_error',
                style: const TextStyle(color: Colors.white70))
            : _payload == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: QrImageView(
                          data: _payload!,
                          version: QrVersions.auto,
                          size: 230,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Avatar(name: me?.displayName ?? '?', url: me?.avatar, size: 54),
                      const SizedBox(height: 10),
                      Text(me?.displayName ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('扫一扫上面的二维码，加我为好友',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 30),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const ScanScreen()),
                        ),
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('去扫对方的码'),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Scanner — scan someone's QR to add them face-to-face.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController();
  bool _handling = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Extract the user id from a scanned payload like `samachat://add?uid=u_xxx`.
  String? _parseUid(String? raw) => parseAddPayload(raw);

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    for (final barcode in capture.barcodes) {
      final uid = _parseUid(barcode.rawValue);
      if (uid == null) continue;
      _handling = true;
      await _resolveAndAdd(uid);
      return;
    }
  }

  Future<void> _resolveAndAdd(String uid) async {
    final s = context.read<AppState>();
    setState(() => _status = '识别中…');
    try {
      final user = await s.api.resolveUser(uid);
      if (!mounted) return;
      if (user.id == s.me?.id) {
        setState(() {
          _status = '这是你自己的二维码 🙂';
          _handling = false;
        });
        return;
      }
      final isFriend = s.friends.any((f) => f.id == user.id);
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('添加好友'),
          content: Text(isFriend
              ? '${user.displayName}（@${user.username}）\n你们已经是好友了'
              : '找到用户 ${user.displayName}（@${user.username}）'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('取消')),
            if (isFriend)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'chat'),
                  child: const Text('发消息'))
            else
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'add'),
                  child: const Text('加为好友')),
          ],
        ),
      );
      if (action == 'add') {
        await s.api.sendFriendRequest(user.id);
        if (!mounted) return;
        setState(() => _status = '好友请求已发送给 ${user.displayName} ✅');
        await s.refreshRequests();
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.pop(context);
      } else if (action == 'chat') {
        final conv = await s.openPrivateChat(user);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)),
        );
      } else {
        setState(() {
          _status = '对准二维码再试一次';
          _handling = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message;
          _handling = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '出错了: $e';
          _handling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫一扫'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // scan frame overlay
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              color: Colors.black54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('将对方的二维码放入框内',
                      style: TextStyle(color: Colors.white70)),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(_status!,
                        style: const TextStyle(
                            color: Colors.greenAccent, fontSize: 15)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
